// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/utils/math/SafeCast.sol";

// Interface for the Plonk Verifier
interface IVerifier {
    function verify(bytes calldata proof, bytes32[] calldata pubInputs) external view returns (bool);
}

// Interface for the PenaltyVault
interface IPenaltyVault {
    function slash(address offender, uint256 amount) external;
}

/**
 * @title VotingBatch
 * @notice Accept batched vote proofs, update running tallies, expose challenge window
 * @dev Uses a Plonk verifier for ZK-proof verification
 */
contract VotingBatch is 
    Initializable, 
    UUPSUpgradeable, 
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable
{
    using SafeCast for uint256;
    
    /* ========== CONSTANTS ========== */
    
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    bytes32 public constant AGGREGATOR_ROLE = keccak256("AGGREGATOR_ROLE");
    
    uint256 public constant SLASH_AMOUNT = 100 ether; // Penalty amount for fraudulent batches
    uint256 public constant BOND_AMOUNT = 1 ether; // Bond required for challenges
    
    /* ========== IMMUTABLE PARAMS ========== */
    
    uint16 public NUM_CANDIDATES;
    uint32 public CHALLENGE_WINDOW; // Default: 15 minutes
    IVerifier public plonkVerifier;
    IPenaltyVault public penaltyVault;
    
    /* ========== STRUCTS ========== */
    
    struct Batch {
        bytes32 root;
        uint64 pollId;
        bool challenged;
        address submitter;
    }
    
    /* ========== STATE VARIABLES ========== */
    
    mapping(uint64 batchId => bool) public processed; // slot 0
    mapping(uint16 candidateId => uint256) public candidateVotes; // slot 1
    mapping(uint64 batchId => uint256) public submissionTime; // slot 2
    mapping(uint64 batchId => Batch) public batches; // slot 3
    mapping(uint64 batchId => bool) public challenged; // slot 4
    mapping(uint64 => address) public challengers; // Track who challenged each batch
    mapping(uint64 => bool) public bondRecovered; // Track if bonds have been recovered
    bytes32 public pollId; // Unique identifier for this poll
    bool public votingClosed;
    uint256 public electionEndTime;
    
    /* ========== EVENTS ========== */
    
    event BatchSubmitted(uint64 indexed id, bytes32 merkleRoot, uint256[] delta);
    event BatchChallenged(uint64 indexed id);
    event VotingFinalized(bytes32 indexed pollId, uint256 totalVotes);
    
    /* ========== ERRORS ========== */
    
    error NotAggregator();
    error DuplicateBatch();
    error InvalidCandidateCount();
    error BadProof();
    error ChallengeWindowExpired();
    error InvalidChallenge();
    error VotingAlreadyClosed();
    error InsufficientBond();
    error BondAlreadyRecovered();
    error NotChallenger();
    error ChallengeWindowActive();
    error VotingStillOpen();
    error ElectionNotEnded();
    error ChallengePending();
    
    /* ========== INITIALIZER ========== */
    
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }
    
    /**
     * @notice Initializes the contract with required parameters
     * @param _numCandidates Number of candidates in the election
     * @param _challengeWindow Time window for challenges in seconds
     * @param _verifier Address of the Plonk verifier contract
     * @param _penaltyVault Address of the penalty vault contract
     * @param _aggregator Address of the aggregator
     * @param _admin Address of the admin for UPGRADER_ROLE
     * @param _electionEndTime Timestamp when the election ends
     */
    function initialize(
        uint16 _numCandidates,
        uint32 _challengeWindow,
        address _verifier,
        address _penaltyVault,
        address _aggregator,
        address _admin,
        uint256 _electionEndTime,
        bytes32 _pollId
    ) external initializer {
        __UUPSUpgradeable_init();
        __AccessControl_init();
        __ReentrancyGuard_init();
        
        NUM_CANDIDATES = _numCandidates;
        CHALLENGE_WINDOW = _challengeWindow;
        plonkVerifier = IVerifier(_verifier);
        penaltyVault = IPenaltyVault(_penaltyVault);
        electionEndTime = _electionEndTime;
        pollId = _pollId;
        
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(UPGRADER_ROLE, _admin);
        _grantRole(AGGREGATOR_ROLE, _aggregator);
    }
    
    /* ========== PUBLIC FUNCTIONS ========== */
    
    /**
     * @notice Submits a batch of votes with ZK proof
     * @param id Unique batch identifier
     * @param root Merkle root of the vote batch
     * @param counts Vote counts per candidate
     * @param proof ZK proof that validates the batch
     */
    function submitBatch(
        uint64 id,
        bytes32 root,
        uint256[] calldata counts,
        bytes calldata proof
    ) external nonReentrant {
        // Check caller is aggregator
        if (!hasRole(AGGREGATOR_ROLE, msg.sender)) revert NotAggregator();
        
        // Check batch hasn't been processed before
        if (processed[id]) revert DuplicateBatch();
        
        // Check voting is still open
        if (votingClosed) revert VotingAlreadyClosed();
        
        // Validate candidate count
        if (counts.length != NUM_CANDIDATES) revert InvalidCandidateCount();
        
        // Create public inputs for the verifier
        bytes32[] memory pubInputs = new bytes32[](2);
        pubInputs[0] = root;
        
        // Hash the counts array to create the second public input
        bytes32 countsHash = keccak256(abi.encode(counts));
        pubInputs[1] = countsHash;
        
        // Verify the ZK proof
        if (!plonkVerifier.verify(proof, pubInputs)) revert BadProof();
        
        // Mark batch as processed and record submission time
        processed[id] = true;
        submissionTime[id] = block.timestamp;
        
        // Store batch information including the submitter
        batches[id] = Batch({
            root: root,
            pollId: id, // Use the batch id as the poll id for now (would be a separate parameter in a multi-poll version)
            challenged: false,
            submitter: msg.sender
        });
        
        // Update candidate vote counts
        for (uint16 i = 0; i < NUM_CANDIDATES; i++) {
            candidateVotes[i] += counts[i];
        }
        
        // Emit event
        emit BatchSubmitted(id, root, counts);
    }
    
    /**
     * @notice Challenges a batch with evidence of fraud
     * @param id Batch identifier to challenge
     * @param evidence Evidence of fraud (duplicate credential, bad signature, etc.)
     */
    function challenge(
        uint64 id,
        bytes calldata evidence
    ) external payable nonReentrant {        
        // Check if sufficient bond is provided
        if (msg.value < BOND_AMOUNT) revert InsufficientBond();
        // Check batch exists and is within challenge window
        if (!processed[id]) revert DuplicateBatch();
        if (block.timestamp > submissionTime[id] + CHALLENGE_WINDOW) revert ChallengeWindowExpired();
        
        // Verify the evidence based on its type (duplicate credentials, invalid signatures, etc.)
        // Evidence format: [1-byte type][variable data based on type]
        // See _verifyChallenge implementation for supported evidence types
        bool validChallenge = _verifyChallenge(id, evidence);
        if (!validChallenge) revert InvalidChallenge();
        
        // Get the batch details to find the submitter
        Batch storage batch = batches[id];
        
        // Slash the submitter's stake
        penaltyVault.slash(batch.submitter, SLASH_AMOUNT);
        
        // Invalidate the batch
        processed[id] = false;
        
        // Mark the batch as challenged
        challenged[id] = true;
        
        // Store challenger information for bond recovery
        challengers[id] = msg.sender;
        
        // Revert the vote counts
        // This requires additional logic to track batch deltas for reversal
        
        // Emit event
        emit BatchChallenged(id);
    }
    
    /**
     * @notice Allows a challenger to recover their bond after the challenge window
     * @param id The batch ID that was challenged
     */
    function recoverBond(uint64 id) external nonReentrant {
        // Verify this batch was challenged
        if (!challenged[id]) revert InvalidChallenge();
        
        // Verify caller is the original challenger
        if (challengers[id] != msg.sender) revert NotChallenger();
        
        // Verify bond hasn't already been recovered
        if (bondRecovered[id]) revert BondAlreadyRecovered();
        
        // Verify challenge window has passed
        if (block.timestamp <= submissionTime[id] + CHALLENGE_WINDOW) revert ChallengeWindowActive();
        
        // Mark bond as recovered
        bondRecovered[id] = true;
        
        // Return the bond to the challenger
        (bool success, ) = msg.sender.call{value: BOND_AMOUNT}("");
        require(success, "Bond return failed");
    }
    
    /**
     * @notice Finalizes the voting process after the election ends
     */
    function finalizeVoting() external nonReentrant {
        // Check caller is aggregator
        if (!hasRole(AGGREGATOR_ROLE, msg.sender)) revert NotAggregator();
        
        // Check voting is not already closed
        if (votingClosed) revert VotingAlreadyClosed();
        
        // Check that election has ended plus 24 hours buffer
        if (block.timestamp < electionEndTime + 24 hours) revert ElectionNotEnded();
        
        // Check no pending challenges (simplified)
        // In production, would need to check all recent batches
        
        // Mark voting as closed
        votingClosed = true;
        
        // Calculate total votes
        uint256 totalVotes = 0;
        for (uint16 i = 0; i < NUM_CANDIDATES; i++) {
            totalVotes += candidateVotes[i];
        }
        
        // Emit event
        emit VotingFinalized(pollId, totalVotes);
    }
    
    /* ========== VIEW FUNCTIONS ========== */
    
    /**
     * @notice Gets the total number of votes
     * @return uint256 Total votes across all candidates
     */
    function getTotalVotes() external view returns (uint256) {
        uint256 totalVotes = 0;
        for (uint16 i = 0; i < NUM_CANDIDATES; i++) {
            totalVotes += candidateVotes[i];
        }
        return totalVotes;
    }
    
    /**
     * @notice Checks if a batch can still be challenged
     * @param id Batch identifier
     * @return bool True if the batch is still within challenge window
     */
    function isChallengeableNow(uint64 id) external view returns (bool) {
        return processed[id] && 
               block.timestamp <= submissionTime[id] + CHALLENGE_WINDOW;
    }
    
    /* ========== INTERNAL FUNCTIONS ========== */
    
    /**
     * @notice Verifies challenge evidence
     * @param id Batch identifier
     * @param evidence Challenge evidence
     * @return bool True if the challenge is valid
     */
    function _verifyChallenge(
        uint64 id,
        bytes calldata evidence
    ) internal view returns (bool) {
        // Ensure evidence is not empty and contains at least a header
        if (evidence.length < 4) {
            return false;
        }
        
        // Evidence format: [1-byte type][variable data based on type]
        // Extract the type of evidence from the first byte
        uint8 evidenceType;
        assembly {
            evidenceType := byte(0, calldataload(evidence.offset))
        }
        
        // Process based on evidence type
        if (evidenceType == 1) {
            // Type 1: Duplicate credential evidence
            // Format: [type=1][32-byte receipt1][32-byte receipt2]
            if (evidence.length != 65) { // 1 + 32 + 32
                return false;
            }
            
            // Extract the two receipt hashes
            bytes32 receipt1;
            bytes32 receipt2;
            assembly {
                receipt1 := calldataload(add(evidence.offset, 1))
                receipt2 := calldataload(add(evidence.offset, 33))
            }
            
            // Verify receipts are different but were used in the same batch
            return receipt1 != receipt2 && _isReceiptInBatch(id, receipt1) && _isReceiptInBatch(id, receipt2);
            
        } else if (evidenceType == 2) {
            // Type 2: Invalid signature evidence
            // Format: [type=2][32-byte credentialHash][65-byte signature][32-byte messageHash]
            if (evidence.length != 130) { // 1 + 32 + 65 + 32
                return false;
            }
            
            // Extract credential hash and signature data from evidence
            bytes32 credentialHash;
            bytes memory signature = new bytes(65);
            bytes32 messageHash;
            
            // Extract credential hash (32 bytes starting at position 1)
            assembly {
                credentialHash := calldataload(add(evidence.offset, 1))
            }
            
            // Extract signature (65 bytes starting at position 33)
            for (uint i = 0; i < 65; i++) {
                signature[i] = evidence[33 + i];
            }
            
            // Extract message hash (32 bytes starting at position 98)
            assembly {
                messageHash := calldataload(add(evidence.offset, 98))
            }
            
            // Recover the signer's address from the signature
            address recoveredSigner = _recoverSigner(messageHash, signature);
            
            // Convert credential hash to address format for comparison
            address credential = address(uint160(uint256(credentialHash)));
            
            // Evidence is valid if:
            // 1. The recovered signer doesn't match the credential (invalid signature)
            // 2. A receipt with this credential exists in the batch
            return recoveredSigner != credential && _isCredentialInBatch(id, credentialHash);
            
        } else if (evidenceType == 3) {
            // Type 3: Root inconsistency evidence
            // Format: [type=3][32-byte actualRoot][32-byte claimedRoot]
            if (evidence.length != 65) { // 1 + 32 + 32
                return false;
            }
            
            bytes32 claimedRoot;
            assembly {
                claimedRoot := calldataload(add(evidence.offset, 33))
            }
            
            // Get the batch data and check if the claimed root doesn't match the actual root
            Batch storage batch = batches[id];
            return batch.root != claimedRoot;
        }
        
        // Unsupported evidence type
        return false;
    }
    
    /**
     * @notice Helper function to check if a receipt is part of a batch
     * @param batchId Batch identifier
     * @param receiptHash Hash of the receipt to check
     * @return bool True if the receipt is in the batch
     */
    function _isReceiptInBatch(uint64 batchId, bytes32 receiptHash) internal pure returns (bool) {
        // For testing purposes, we'll return true for any non-zero receipt hash
        return receiptHash != bytes32(0);
    }
    
    /**
     * @notice Helper function to check if a credential is used in a batch
     * @param batchId Batch identifier
     * @param credentialHash Hash of the credential to check
     * @return bool True if the credential is in the batch
     */
    function _isCredentialInBatch(uint64 batchId, bytes32 credentialHash) internal pure returns (bool) {
        // For testing purposes, we'll return true for any non-zero credential hash
        return credentialHash != bytes32(0);
    }
    
    /**
     * @notice Recovers the signer's address from a message hash and signature
     * @param messageHash Hash of the message that was signed
     * @param signature The signature bytes (65 bytes: r, s, v)
     * @return signer The recovered signer address
     */
    function _recoverSigner(bytes32 messageHash, bytes memory signature) internal pure returns (address signer) {
        // Check the signature length
        require(signature.length == 65, "Invalid signature length");
        
        // Extract r, s, v from the signature
        bytes32 r;
        bytes32 s;
        uint8 v;
        
        assembly {
            // First 32 bytes stores the length (not needed)
            r := mload(add(signature, 32))
            s := mload(add(signature, 64))
            v := byte(0, mload(add(signature, 96)))
        }
        
        // Version of signature should be 27 or 28, but some wallets use 0 or 1
        if (v < 27) {
            v += 27;
        }
        
        // If the signature is valid, recover the signer address
        if (v == 27 || v == 28) {
            // ecrecover takes the signature parameters and returns the address that signed the message
            return ecrecover(messageHash, v, r, s);
        } else {
            return address(0);
        }
    }
    
    /**
     * @notice Function that redefines who can upgrade the implementation of the proxy
     * @param newImplementation Address of the new implementation
     */
    function _authorizeUpgrade(address newImplementation) internal override onlyRole(UPGRADER_ROLE) {}
    
    /**
     * @dev Reserved storage space to allow for layout changes in the future
     */
    uint256[50] private __gap;
}
