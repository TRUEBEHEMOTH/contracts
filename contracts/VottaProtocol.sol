// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";

/**
 * @title VottaProtocol
 * @notice Central registry and coordination contract for the Votta e-voting system
 * @dev Manages all other contracts and factories in the protocol
 */
contract VottaProtocol is 
    Initializable, 
    UUPSUpgradeable, 
    AccessControlUpgradeable,
    PausableUpgradeable
{
    /* ========== CONSTANTS ========== */
    
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    bytes32 public constant EMERGENCY_ROLE = keccak256("EMERGENCY_ROLE");
    
    /* ========== STATE VARIABLES ========== */
    
    // Core contract addresses
    address public credentialRegistry;
    address public votingFactory;
    address public penaltyVault;
    address public plonkVerifier;
    address public paymaster;
    
    // Protocol configuration
    string public protocolVersion;
    bool public mainnetMode; // True if deployed on mainnet, false for testnet
    
    // Governance parameters
    uint256 public emergencyTimelock; // Time delay for emergency actions
    mapping(bytes32 => uint256) public emergencyActions; // Action hash => timestamp
    
    // Protocol statistics
    uint256 public totalPolls;
    uint256 public totalVoters;
    uint256 public totalVotes;
    
    /* ========== EVENTS ========== */
    
    event ContractRegistered(string contractType, address indexed contractAddress);
    event ProtocolUpgraded(string newVersion);
    event EmergencyActionScheduled(bytes32 indexed actionHash, uint256 executionTime);
    event EmergencyActionExecuted(bytes32 indexed actionHash);
    event EmergencyActionCancelled(bytes32 indexed actionHash);
    event ProtocolStatisticsUpdated(uint256 polls, uint256 voters, uint256 votes);
    
    /* ========== ERRORS ========== */
    
    error InvalidAddress();
    error ActionNotScheduled();
    error TimelockNotExpired();
    error ActionExpired();
    
    /* ========== INITIALIZER ========== */
    
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }
    
    /**
     * @notice Initializes the protocol contract
     * @param _admin Address of the admin
     * @param _emergencyTimelock Time delay for emergency actions in seconds
     * @param _mainnetMode Whether this is deployed on mainnet
     */
    function initialize(
        address _admin,
        uint256 _emergencyTimelock,
        bool _mainnetMode
    ) external initializer {
        __UUPSUpgradeable_init();
        __AccessControl_init();
        __Pausable_init();
        
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(ADMIN_ROLE, _admin);
        _grantRole(UPGRADER_ROLE, _admin);
        _grantRole(EMERGENCY_ROLE, _admin);
        
        emergencyTimelock = _emergencyTimelock;
        mainnetMode = _mainnetMode;
        protocolVersion = "1.0.0";
    }
    
    /* ========== CONTRACT REGISTRATION ========== */
    
    /**
     * @notice Registers the credential registry contract
     * @param _credentialRegistry Address of the credential registry
     */
    function registerCredentialRegistry(address _credentialRegistry) external onlyRole(ADMIN_ROLE) {
        if (_credentialRegistry == address(0)) revert InvalidAddress();
        credentialRegistry = _credentialRegistry;
        emit ContractRegistered("CredentialRegistry", _credentialRegistry);
    }
    
    /**
     * @notice Registers the voting factory contract
     * @param _votingFactory Address of the voting factory
     */
    function registerVotingFactory(address _votingFactory) external onlyRole(ADMIN_ROLE) {
        if (_votingFactory == address(0)) revert InvalidAddress();
        votingFactory = _votingFactory;
        emit ContractRegistered("VotingFactory", _votingFactory);
    }
    
    /**
     * @notice Registers the penalty vault contract
     * @param _penaltyVault Address of the penalty vault
     */
    function registerPenaltyVault(address _penaltyVault) external onlyRole(ADMIN_ROLE) {
        if (_penaltyVault == address(0)) revert InvalidAddress();
        penaltyVault = _penaltyVault;
        emit ContractRegistered("PenaltyVault", _penaltyVault);
    }
    
    /**
     * @notice Registers the Plonk verifier contract
     * @param _plonkVerifier Address of the Plonk verifier
     */
    function registerPlonkVerifier(address _plonkVerifier) external onlyRole(ADMIN_ROLE) {
        if (_plonkVerifier == address(0)) revert InvalidAddress();
        plonkVerifier = _plonkVerifier;
        emit ContractRegistered("PlonkVerifier", _plonkVerifier);
    }
    
    /**
     * @notice Registers the paymaster contract
     * @param _paymaster Address of the paymaster
     */
    function registerPaymaster(address _paymaster) external onlyRole(ADMIN_ROLE) {
        if (_paymaster == address(0)) revert InvalidAddress();
        paymaster = _paymaster;
        emit ContractRegistered("Paymaster", _paymaster);
    }
    
    /* ========== PROTOCOL MANAGEMENT ========== */
    
    /**
     * @notice Updates the protocol version
     * @param _newVersion New version string
     */
    function updateProtocolVersion(string calldata _newVersion) external onlyRole(ADMIN_ROLE) {
        protocolVersion = _newVersion;
        emit ProtocolUpgraded(_newVersion);
    }
    
    /**
     * @notice Pauses the protocol in case of emergency
     */
    function pauseProtocol() external onlyRole(EMERGENCY_ROLE) {
        _pause();
    }
    
    /**
     * @notice Unpauses the protocol after emergency is resolved
     */
    function unpauseProtocol() external onlyRole(ADMIN_ROLE) {
        _unpause();
    }
    
    /**
     * @notice Updates protocol statistics
     * @param _totalPolls Total number of polls
     * @param _totalVoters Total number of registered voters
     * @param _totalVotes Total number of votes cast
     */
    function updateStatistics(
        uint256 _totalPolls,
        uint256 _totalVoters,
        uint256 _totalVotes
    ) external onlyRole(ADMIN_ROLE) {
        totalPolls = _totalPolls;
        totalVoters = _totalVoters;
        totalVotes = _totalVotes;
        
        emit ProtocolStatisticsUpdated(_totalPolls, _totalVoters, _totalVotes);
    }
    
    /* ========== EMERGENCY GOVERNANCE ========== */
    
    /**
     * @notice Schedules an emergency action
     * @param actionHash Hash of the action to be performed
     */
    function scheduleEmergencyAction(bytes32 actionHash) external onlyRole(EMERGENCY_ROLE) {
        emergencyActions[actionHash] = block.timestamp + emergencyTimelock;
        emit EmergencyActionScheduled(actionHash, emergencyActions[actionHash]);
    }
    
    /**
     * @notice Executes a scheduled emergency action
     * @param actionHash Hash of the action to be performed
     */
    function executeEmergencyAction(bytes32 actionHash) external onlyRole(EMERGENCY_ROLE) {
        uint256 scheduledTime = emergencyActions[actionHash];
        
        if (scheduledTime == 0) revert ActionNotScheduled();
        if (block.timestamp < scheduledTime) revert TimelockNotExpired();
        if (block.timestamp > scheduledTime + 1 days) revert ActionExpired();
        
        // Clear the scheduled action
        delete emergencyActions[actionHash];
        
        emit EmergencyActionExecuted(actionHash);
        
        // The actual action is performed by the caller after this check
    }
    
    /**
     * @notice Cancels a scheduled emergency action
     * @param actionHash Hash of the action to cancel
     */
    function cancelEmergencyAction(bytes32 actionHash) external onlyRole(ADMIN_ROLE) {
        if (emergencyActions[actionHash] == 0) revert ActionNotScheduled();
        
        delete emergencyActions[actionHash];
        emit EmergencyActionCancelled(actionHash);
    }
    
    /* ========== PROTOCOL INFORMATION ========== */
    
    /**
     * @notice Gets all registered contract addresses
     * @return _credentialRegistry Address of the credential registry
     * @return _votingFactory Address of the voting factory
     * @return _penaltyVault Address of the penalty vault
     * @return _plonkVerifier Address of the Plonk verifier
     * @return _paymaster Address of the paymaster
     */
    function getAllContracts() external view returns (
        address _credentialRegistry,
        address _votingFactory,
        address _penaltyVault,
        address _plonkVerifier,
        address _paymaster
    ) {
        return (
            credentialRegistry,
            votingFactory,
            penaltyVault,
            plonkVerifier,
            paymaster
        );
    }
    
    /**
     * @notice Checks if the protocol is fully configured
     * @return bool True if all core contracts are registered
     */
    function isProtocolConfigured() external view returns (bool) {
        return (
            credentialRegistry != address(0) &&
            votingFactory != address(0) &&
            penaltyVault != address(0) &&
            plonkVerifier != address(0) &&
            paymaster != address(0)
        );
    }
    
    /**
     * @notice Gets protocol status information
     * @return _version Protocol version string
     * @return _paused Whether the protocol is paused
     * @return _mainnetMode Whether the protocol is in mainnet mode
     * @return _totalPolls Total number of polls created
     * @return _totalVoters Total number of registered voters
     * @return _totalVotes Total number of votes cast
     */
    function getProtocolStatus() external view returns (
        string memory _version,
        bool _paused,
        bool _mainnetMode,
        uint256 _totalPolls,
        uint256 _totalVoters,
        uint256 _totalVotes
    ) {
        return (
            protocolVersion,
            paused(),
            mainnetMode,
            totalPolls,
            totalVoters,
            totalVotes
        );
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
