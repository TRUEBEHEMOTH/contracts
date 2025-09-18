// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title VotingPaymaster
 * @notice Paymaster contract for covering gas costs of voting operations
 * @dev Implements ERC-4337 paymaster interface to sponsor voting transactions
 */
contract VotingPaymaster is Ownable {
    using ECDSA for bytes32;

    /* ========== STATE VARIABLES ========== */
    
    // EntryPoint contract address
    address public entryPoint;
    
    // VotingFactory contract address
    address public votingFactory;
    
    // Mapping of allowed polls (pollId => allowed)
    mapping(bytes32 => bool) public allowedPolls;
    
    // Mapping of allowed wallets (wallet => allowed)
    mapping(address => bool) public allowedWallets;
    
    /* ========== EVENTS ========== */
    
    event PaymasterFunded(address indexed funder, uint256 amount);
    event PollAllowanceSet(bytes32 indexed pollId, bool allowed);
    event WalletAllowanceSet(address indexed wallet, bool allowed);
    
    /* ========== ERRORS ========== */
    
    error InvalidEntryPoint();
    error InvalidUserOp();
    error InsufficientBalance();
    error NotAllowedPoll();
    error NotAllowedWallet();
    
    /* ========== CONSTRUCTOR ========== */
    
    /**
     * @notice Constructs the VotingPaymaster contract
     * @param _entryPoint Address of the ERC-4337 EntryPoint contract
     * @param _votingFactory Address of the VotingFactory contract
     */
    constructor(address _entryPoint, address _votingFactory) Ownable(msg.sender) {
        entryPoint = _entryPoint;
        votingFactory = _votingFactory;
    }
    
    /* ========== EXTERNAL FUNCTIONS ========== */
    
    /**
     * @notice Validates a user operation for the ERC-4337 Entry Point
     * @param userOp User operation to validate
     * @param userOpHash Hash of the user operation
     * @param maxCost Maximum cost of the operation
     * @return context Validation context for postOp
     */
    function validatePaymasterUserOp(
        UserOperation calldata userOp,
        bytes32 userOpHash,
        uint256 maxCost
    ) external returns (bytes memory context, uint256 validationData) {
        // Verify the EntryPoint is calling
        if (msg.sender != entryPoint) revert InvalidEntryPoint();
        
        // Check if the paymaster has enough balance
        if (address(this).balance < maxCost) revert InsufficientBalance();
        
        // Extract the target function selector from callData
        bytes4 selector = bytes4(userOp.callData[:4]);
        
        // Check if this is a vote operation
        if (selector != bytes4(keccak256("vote(uint8,uint128,bytes32,bytes32)"))) {
            revert InvalidUserOp();
        }
        
        // Extract the poll ID from the callData
        // Assuming vote function has signature: vote(uint8 choice, uint128 nonce, bytes32 idHash, bytes32 pollId)
        bytes32 pollId;
        
        // Extract pollId from the callData (position after selector, choice, nonce, and idHash)
        // This is a safer approach than using assembly for complex calldata access
        if (userOp.callData.length >= 132) { // 4 (selector) + 32*4 (params)
            // Skip selector (4 bytes) and the first three parameters (3*32 bytes)
            uint256 pollIdPos = 4 + 32*3;
            bytes memory pollIdData = new bytes(32);
            for (uint i = 0; i < 32; i++) {
                if (pollIdPos + i < userOp.callData.length) {
                    pollIdData[i] = userOp.callData[pollIdPos + i];
                }
            }
            assembly {
                pollId := mload(add(pollIdData, 32))
            }
        }
        
        // Check if the poll is allowed
        if (!allowedPolls[pollId]) revert NotAllowedPoll();
        
        // Check if the wallet is allowed
        if (!allowedWallets[userOp.sender]) revert NotAllowedWallet();
        
        // Return validation data (0 means valid until infinity)
        return (abi.encode(userOp.sender, maxCost, pollId), 0);
    }
    
    /**
     * @notice Post-operation hook for the ERC-4337 Entry Point
     * @param mode Operation mode (0 for success)
     * @param context Validation context from validatePaymasterUserOp
     * @param actualGasCost Actual gas cost of the operation
     */
    function postOp(
        PostOpMode mode,
        bytes calldata context,
        uint256 actualGasCost
    ) external {
        // Verify the EntryPoint is calling
        if (msg.sender != entryPoint) revert InvalidEntryPoint();
        
        // No additional logic needed for now
        // This could be extended to implement rate limiting, etc.
    }
    
    /**
     * @notice Deposits funds to the EntryPoint for gas payments
     */
    function deposit() external payable {
        // Forward funds to the EntryPoint
        (bool success, ) = entryPoint.call{value: msg.value}("");
        require(success, "Deposit failed");
        
        emit PaymasterFunded(msg.sender, msg.value);
    }
    
    /**
     * @notice Sets allowance for a poll
     * @param pollId ID of the poll
     * @param allowed Whether the poll is allowed
     */
    function setPollAllowance(bytes32 pollId, bool allowed) external onlyOwner {
        allowedPolls[pollId] = allowed;
        emit PollAllowanceSet(pollId, allowed);
    }
    
    /**
     * @notice Sets allowance for a wallet
     * @param wallet Address of the wallet
     * @param allowed Whether the wallet is allowed
     */
    function setWalletAllowance(address wallet, bool allowed) external onlyOwner {
        allowedWallets[wallet] = allowed;
        emit WalletAllowanceSet(wallet, allowed);
    }
    
    /**
     * @notice Withdraws funds from the EntryPoint
     * @param amount Amount to withdraw
     */
    function withdrawFromEntryPoint(uint256 amount) external onlyOwner {
        // Call the EntryPoint to withdraw funds
        // This assumes the EntryPoint has a withdrawTo function
        (bool success, ) = entryPoint.call(
            abi.encodeWithSignature("withdrawTo(address,uint256)", address(this), amount)
        );
        require(success, "Withdrawal failed");
        
        // Transfer the funds to the owner
        (success, ) = owner().call{value: amount}("");
        require(success, "Transfer failed");
    }
    
    /* ========== FALLBACK & RECEIVE ========== */
    
    receive() external payable {}
}

/**
 * @dev Simplified UserOperation struct for ERC-4337
 */
struct UserOperation {
    address sender;
    uint256 nonce;
    bytes callData;
    bytes signature;
    address paymaster;
    bytes paymasterData;
    uint256 maxFeePerGas;
    uint256 maxPriorityFeePerGas;
    // Other fields omitted for brevity
}

/**
 * @dev PostOpMode enum for ERC-4337
 */
enum PostOpMode {
    opSucceeded,
    opReverted,
    postOpReverted
}
