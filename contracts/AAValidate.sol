// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title AAValidate
 * @notice Validation hook for ERC-4337 Account Abstraction wallets
 * @dev Used inside custom AA-wallet to validate voting operations
 */

// Interface for CredentialRegistry functions we need
interface ICredentialRegistry {
    function isValid(bytes32 idHash, address voter) external view returns (bool);
}
library AAValidate {
    /* ========== ERRORS ========== */
    
    error InvalidCredential();
    error AlreadyVoted();
    error InvalidSignature();
    
    /* ========== STRUCTS ========== */
    
    /**
     * @dev UserOperation struct (simplified version of ERC-4337)
     */
    struct UserOp {
        address sender;
        uint256 nonce;
        bytes callData;
        bytes signature;
        // Other fields omitted for brevity
    }
    
    /**
     * @dev Storage structure for tracking used credentials
     */
    struct VoteStorage {
        mapping(bytes32 pollId => mapping(bytes32 idHash => uint256)) used;
        address credentialRegistry;
    }
    
    /* ========== FUNCTIONS ========== */
    
    /**
     * @notice Records a vote in the storage to prevent double voting
     * @param storage_ VoteStorage struct to work with
     * @param idHash Hash of the voter's credential ID
     * @param pollId ID of the poll being voted in
     */
    function recordVote(
        VoteStorage storage storage_,
        bytes32 idHash,
        bytes32 pollId
    ) internal {
        // Record that this credential has been used for this poll
        storage_.used[pollId][idHash] = block.timestamp;
    }
    
    /**
     * @notice Validates a user operation for a vote
     * @param storage_ VoteStorage struct to work with
     * @param userOp The user operation to validate
     * @return uint256 Validation result (0 for valid)
     */
    function validateUserOp(
        VoteStorage storage storage_,
        UserOp calldata userOp
    ) internal view returns (uint256) {
        // Extract the vote data from the calldata
        // Assuming callData format: vote(bytes32 pollId, bytes32 idHash, uint8 choice, bytes calldata signature)
        
        // Safely extract parameters instead of using assembly
        bytes calldata callData = userOp.callData;
        // We need at least 4 bytes (selector) + 32 bytes (pollId) + 32 bytes (idHash)
        require(callData.length >= 68, "Invalid calldata length");
        
        // Skip the function selector (4 bytes) and extract the parameters
        bytes32 pollId = bytes32(callData[4:36]);
        bytes32 idHash = bytes32(callData[36:68]);
        
        // Check if this credential has already been used for this poll
        if (storage_.used[pollId][idHash] != 0) {
            revert AlreadyVoted();
        }
        
        // Check if the credential is valid in the registry
        ICredentialRegistry registry = ICredentialRegistry(storage_.credentialRegistry);
        if (!registry.isValid(idHash, userOp.sender)) {
            revert InvalidCredential();
        }
        
        // Signature validation would go here in a complete implementation
        
        return 0; // Valid
    }
    
    /**
     * @notice Validates a user operation for voting
     * @param op User operation to validate
     * @param voteStorage Vote storage containing used credentials mapping
     * @return valid Returns 0 if valid
     */
    function validateUserOp(
        UserOp calldata op,
        VoteStorage storage voteStorage
    ) external view returns (uint256 valid) {
        // Decode voting parameters from calldata:
        // Assuming callData is: abi.encodeWithSelector(vote.selector, choice, nonce, idHash, pollId)
        // Skip the first 4 bytes (function selector)
        (uint8 choice, uint128 nonce, bytes32 idHash, bytes32 pollId) = abi.decode(
            op.callData[4:],
            (uint8, uint128, bytes32, bytes32)
        );
        
        // Check if the credential is valid
        if (!ICredentialRegistry(voteStorage.credentialRegistry).isValid(idHash, msg.sender)) {
            revert InvalidCredential();
        }
        
        // Check if the voter has already voted in this poll
        if (voteStorage.used[pollId][idHash] != 0) {
            revert AlreadyVoted();
        }
        
        // Signature validation is handled by the EntryPoint contract
        // Here we could add additional validation if needed
        
        // Return 0 to indicate the operation is valid
        // The actual use of voteStorage.used[idHash] = 1 will happen in the post-op execution
        return 0;
    }
    
    /**
     * @notice Records the vote to prevent double voting
     * @param idHash Hash of the voter's identification
     * @param pollId ID of the poll being voted in
     * @param voteStorage Vote storage containing used credentials mapping
     */
    function recordVote(
        bytes32 idHash,
        bytes32 pollId,
        VoteStorage storage voteStorage
    ) external {
        voteStorage.used[pollId][idHash] = 1;
    }
}

/**
 * @title VotterAA
 * @notice Example implementation of an AA wallet compatible with the  e-voting system
 * @dev This is a simplified example and should be expanded for production use
 */
contract VotterAA {
    using AAValidate for AAValidate.VoteStorage;
    
    /* ========== STATE VARIABLES ========== */
    
    AAValidate.VoteStorage internal voteStorage;
    address public owner;
    
    /* ========== EVENTS ========== */
    
    event VoteCast(uint8 indexed choice, bytes32 indexed idHash);
    
    /* ========== CONSTRUCTOR ========== */
    
    constructor(address _credentialRegistry, address _owner) {
        voteStorage.credentialRegistry = _credentialRegistry;
        owner = _owner;
    }
    
    /* ========== PUBLIC FUNCTIONS ========== */
    
    /**
     * @notice Validates a user operation for the ERC-4337 Entry Point
     * @param userOp User operation to validate
     * @param userOpHash Hash of the user operation
     * @param missingAccountFunds Amount of funds missing from the account
     * @return validationData Validation result data
     */
    function validateUserOp(
        AAValidate.UserOp calldata userOp,
        bytes32 userOpHash,
        uint256 missingAccountFunds
    ) external returns (uint256 validationData) {
        // Check if this is a vote operation
        bytes4 selector = bytes4(userOp.callData[:4]);
        if (selector == this.vote.selector) {
            return AAValidate.validateUserOp(voteStorage, userOp);
        } else {
            // For non-voting operations, validate owner signature
            // This is a simplified example
            bytes32 hash = keccak256(abi.encodePacked(userOpHash, address(this)));
            if (owner != _recoverSignature(hash, userOp.signature)) {
                return 1; // Invalid signature
            }
            return 0;
        }
    }
    
    /**
     * @notice Casts a vote using the wallet
     * @param choice The candidate choice (index)
     * @param nonce A random nonce for privacy
     * @param idHash Hash of the voter's identification
     * @param pollId ID of the poll being voted in
     */
    function vote(
        uint8 choice,
        uint128 nonce,
        bytes32 idHash,
        bytes32 pollId
    ) external {
        // This can only be called via the Entry Point during user operation execution
        // Check that caller is Entry Point would be done in production version
        
        // Record the vote to prevent double voting
        AAValidate.recordVote(voteStorage, idHash, pollId);
        
        // Emit vote event
        emit VoteCast(choice, idHash);
        
        // Additional logic for submitting the actual vote would be here
        // This might involve creating a ZK commitment that would be sent to the Aggregator
    }
    
    /* ========== INTERNAL FUNCTIONS ========== */
    
    /**
     * @notice Recovers signer address from signature
     * @param hash Hash that was signed
     * @param signature Signature bytes
     * @return Signer address
     */
    function _recoverSignature(
        bytes32 hash,
        bytes memory signature
    ) internal pure returns (address) {
        // Simplified signature recovery
        // In production, use a robust ECDSA implementation
        bytes32 r;
        bytes32 s;
        uint8 v;
        
        // Extract r, s, v from the signature
        assembly {
            r := mload(add(signature, 32))
            s := mload(add(signature, 64))
            v := byte(0, mload(add(signature, 96)))
        }
        
        // ecrecover takes the signature parameters and returns the address that signed it
        return ecrecover(hash, v, r, s);
    }
}
