// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import "./VotingBatch.sol";

/**
 * @title VotingFactory
 * @notice Factory contract for creating and managing multiple voting polls
 * @dev Creates new VotingBatch instances for different polls/elections
 */
contract VotingFactory is 
    Initializable, 
    UUPSUpgradeable, 
    AccessControlUpgradeable
{
    /* ========== CONSTANTS ========== */
    
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    bytes32 public constant POLL_CREATOR_ROLE = keccak256("POLL_CREATOR_ROLE");
    
    /* ========== STATE VARIABLES ========== */
    
    // Mapping from poll ID to VotingBatch address
    mapping(bytes32 => address) public polls;
    
    // Array of all poll IDs
    bytes32[] public pollIds;
    
    // Implementation address for VotingBatch
    address public votingBatchImplementation;
    
    // Address of the penalty vault
    address public penaltyVault;
    
    // Address of the Plonk verifier
    address public plonkVerifier;
    
    /* ========== EVENTS ========== */
    
    event PollCreated(bytes32 indexed pollId, address indexed votingBatch, string name);
    
    /* ========== ERRORS ========== */
    
    error PollAlreadyExists();
    error InvalidPollId();
    
    /* ========== INITIALIZER ========== */
    
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }
    
    /**
     * @notice Initializes the contract with required parameters
     * @param _votingBatchImplementation Implementation address for VotingBatch
     * @param _penaltyVault Address of the penalty vault
     * @param _plonkVerifier Address of the Plonk verifier
     * @param _admin Address of the admin
     */
    function initialize(
        address _votingBatchImplementation,
        address _penaltyVault,
        address _plonkVerifier,
        address _admin
    ) external initializer {
        __UUPSUpgradeable_init();
        __AccessControl_init();
        
        votingBatchImplementation = _votingBatchImplementation;
        penaltyVault = _penaltyVault;
        plonkVerifier = _plonkVerifier;
        
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(UPGRADER_ROLE, _admin);
        _grantRole(POLL_CREATOR_ROLE, _admin);
    }
    
    /* ========== PUBLIC FUNCTIONS ========== */
    
    /**
     * @notice Creates a new voting poll
     * @param pollId Unique identifier for the poll
     * @param name Human-readable name for the poll
     * @param numCandidates Number of candidates in the poll
     * @param challengeWindow Time window for challenges in seconds
     * @param aggregator Address of the aggregator
     * @param electionEndTime Timestamp when the election ends
     * @return votingBatch Address of the created VotingBatch contract
     */
    function createPoll(
        bytes32 pollId,
        string calldata name,
        uint16 numCandidates,
        uint32 challengeWindow,
        address aggregator,
        uint256 electionEndTime
    ) external onlyRole(POLL_CREATOR_ROLE) returns (address votingBatch) {
        // Check if poll already exists
        if (polls[pollId] != address(0)) revert PollAlreadyExists();
        
        // Create initialization data for the VotingBatch
        bytes memory initData = abi.encodeWithSelector(
            VotingBatch.initialize.selector,
            numCandidates,
            challengeWindow,
            plonkVerifier,
            penaltyVault,
            aggregator,
            msg.sender, // Admin will be the poll creator
            electionEndTime,
            pollId
        );
        
        // Deploy a new proxy pointing to the VotingBatch implementation
        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            votingBatchImplementation,
            address(this), // Admin of the proxy is this factory
            initData
        );
        
        // Store the new poll
        votingBatch = address(proxy);
        polls[pollId] = votingBatch;
        pollIds.push(pollId);
        
        // Emit event
        emit PollCreated(pollId, votingBatch, name);
        
        return votingBatch;
    }
    
    /**
     * @notice Gets the address of a voting poll
     * @param pollId Unique identifier for the poll
     * @return Address of the VotingBatch contract
     */
    function getPoll(bytes32 pollId) external view returns (address) {
        return polls[pollId];
    }
    
    /**
     * @notice Gets the total number of polls
     * @return uint256 Total number of polls
     */
    function getPollCount() external view returns (uint256) {
        return pollIds.length;
    }
    
    /**
     * @notice Gets poll IDs with pagination
     * @param offset Starting index
     * @param limit Maximum number of IDs to return
     * @return bytes32[] Array of poll IDs
     */
    function getPollIds(uint256 offset, uint256 limit) external view returns (bytes32[] memory) {
        uint256 end = offset + limit;
        if (end > pollIds.length) {
            end = pollIds.length;
        }
        
        bytes32[] memory result = new bytes32[](end - offset);
        for (uint256 i = offset; i < end; i++) {
            result[i - offset] = pollIds[i];
        }
        
        return result;
    }
    
    /* ========== INTERNAL FUNCTIONS ========== */
    
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
