// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";

// Interface for the VotingBatch contract to check if voting is closed
interface IVotingBatch {
    function votingClosed() external view returns (bool);
}

/**
 * @title PenaltyVault
 * @notice Escrow stakes for slashable actors (aggregator, sequencer)
 * @dev Handles stake deposits, slashing, and withdrawals
 */
contract PenaltyVault is 
    Initializable, 
    UUPSUpgradeable, 
    AccessControlUpgradeable,
    ReentrancyGuardUpgradeable
{
    /* ========== CONSTANTS ========== */
    
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    bytes32 public constant WATCHTOWER_ROLE = keccak256("WATCHTOWER_ROLE");
    
    uint256 public constant COOLDOWN_PERIOD = 7 days;
    
    /* ========== STATE VARIABLES ========== */
    
    mapping(address => uint256) public stake;
    address public watchTower;
    IVotingBatch public votingBatch;
    mapping(address => uint256) public lastWithdrawalRequest;
    
    /* ========== EVENTS ========== */
    
    event Deposited(address indexed actor, uint256 amount);
    event Slashed(address indexed offender, uint256 amount);
    event WithdrawalRequested(address indexed actor, uint256 amount);
    event Withdrawn(address indexed actor, uint256 amount);
    
    /* ========== ERRORS ========== */
    
    error NotWatchTower();
    error InsufficientStake();
    error VotingNotClosed();
    error CooldownNotPassed();
    error NoWithdrawalRequested();
    
    /* ========== INITIALIZER ========== */
    
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }
    
    /**
     * @notice Initializes the contract with required parameters
     * @param _watchTower Address of the watch tower
     * @param _votingBatch Address of the voting batch contract
     * @param _admin Address of the admin for UPGRADER_ROLE
     */
    function initialize(
        address _watchTower,
        address _votingBatch,
        address _admin
    ) external initializer {
        __UUPSUpgradeable_init();
        __AccessControl_init();
        __ReentrancyGuard_init();
        
        watchTower = _watchTower;
        votingBatch = IVotingBatch(_votingBatch);
        
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(UPGRADER_ROLE, _admin);
        _grantRole(WATCHTOWER_ROLE, _watchTower);
    }
    
    /* ========== PUBLIC FUNCTIONS ========== */
    
    /**
     * @notice Deposits stake funds for an actor
     */
    function deposit() external payable nonReentrant {
        stake[msg.sender] += msg.value;
        emit Deposited(msg.sender, msg.value);
    }
    
    /**
     * @notice Slashes stake from an offender
     * @param offender Address of the offender
     * @param amount Amount to slash
     */
    function slash(
        address offender,
        uint256 amount
    ) external nonReentrant onlyRole(WATCHTOWER_ROLE) {
        // Check if offender has enough stake
        if (stake[offender] < amount) revert InsufficientStake();
        
        // Slash the stake
        stake[offender] -= amount;
        
        // Emit event
        emit Slashed(offender, amount);
    }
    
    /**
     * @notice Requests a withdrawal of stake
     * @param amount Amount to withdraw
     */
    function requestWithdrawal(uint256 amount) external nonReentrant {
        // Check if voting is closed
        if (!votingBatch.votingClosed()) revert VotingNotClosed();
        
        // Check if actor has enough stake
        if (stake[msg.sender] < amount) revert InsufficientStake();
        
        // Record withdrawal request time
        lastWithdrawalRequest[msg.sender] = block.timestamp;
        
        // Emit event
        emit WithdrawalRequested(msg.sender, amount);
    }
    
    /**
     * @notice Withdraws stake after cooldown
     * @param amount Amount to withdraw
     */
    function withdraw(uint256 amount) external nonReentrant {
        // Check if a withdrawal was requested
        if (lastWithdrawalRequest[msg.sender] == 0) revert NoWithdrawalRequested();
        
        // Check if cooldown has passed
        if (block.timestamp < lastWithdrawalRequest[msg.sender] + COOLDOWN_PERIOD) 
            revert CooldownNotPassed();
        
        // Check if actor has enough stake
        if (stake[msg.sender] < amount) revert InsufficientStake();
        
        // Reduce stake
        stake[msg.sender] -= amount;
        
        // Transfer funds
        (bool success, ) = msg.sender.call{value: amount}("");
        require(success, "Transfer failed");
        
        // Emit event
        emit Withdrawn(msg.sender, amount);
    }
    
    /* ========== VIEW FUNCTIONS ========== */
    
    /**
     * @notice Gets the current stake of an actor
     * @param actor Address of the actor
     * @return uint256 Current stake amount
     */
    function getStake(address actor) external view returns (uint256) {
        return stake[actor];
    }
    
    /**
     * @notice Checks if an actor can withdraw their stake
     * @param actor Address of the actor
     * @return bool True if the actor can withdraw
     */
    function canWithdraw(address actor) external view returns (bool) {
        return votingBatch.votingClosed() && 
               lastWithdrawalRequest[actor] > 0 &&
               block.timestamp >= lastWithdrawalRequest[actor] + COOLDOWN_PERIOD;
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
    
    /**
     * @notice Fallback function to accept ETH
     */
    receive() external payable {
        stake[msg.sender] += msg.value;
        emit Deposited(msg.sender, msg.value);
    }
}
