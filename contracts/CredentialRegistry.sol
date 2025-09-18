// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/cryptography/MessageHashUtils.sol";

/**
 * @title CredentialRegistry
 * @notice Sole authoritative registry of voter credentials (unique citizens)
 * @dev Implements EIP-712 signature verification for credential issuance
 */
contract CredentialRegistry is Initializable, UUPSUpgradeable, AccessControlUpgradeable {
    using ECDSA for bytes32;
    using MessageHashUtils for bytes32;

    /* ========== CONSTANTS ========== */
    
    bytes32 public constant UPGRADER_ROLE = keccak256("UPGRADER_ROLE");
    bytes32 public constant REVOKER_ROLE = keccak256("REVOKER_ROLE");
    
    /* ========== TYPES ========== */
    
    enum Status { None, Valid, Revoked }
    
    /* ========== STATE VARIABLES ========== */
    
    mapping(bytes32 idHash => Status) public status;
    address public issuerGov;
    address public issuerNGO;
    
    // EIP-712 typehash and domain separator
    bytes32 private constant CREDENTIAL_TYPEHASH = 
        keccak256("Credential(bytes32 idHash,address voter,uint256 nonce)");
    bytes32 private DOMAIN_SEPARATOR;
    
    /* ========== EVENTS ========== */
    
    event CredentialIssued(bytes32 indexed idHash, address indexed voter);
    event CredentialRevoked(bytes32 indexed idHash);
    
    /* ========== ERRORS ========== */
    
    error AlreadyIssued();
    error InvalidSignatureGov();
    error InvalidSignatureNGO();
    error NotValidCredential();
    error AlreadyRevoked();
    
    /* ========== INITIALIZER ========== */
    
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }
    
    /**
     * @notice Initializes the contract with issuer addresses and domain separator
     * @param _issuerGov Government issuer address
     * @param _issuerNGO NGO issuer address
     * @param _admin Address of the admin for UPGRADER_ROLE
     */
    function initialize(
        address _issuerGov,
        address _issuerNGO,
        address _admin
    ) external initializer {
        __UUPSUpgradeable_init();
        __AccessControl_init();
        
        issuerGov = _issuerGov;
        issuerNGO = _issuerNGO;
        
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(UPGRADER_ROLE, _admin);
        _grantRole(REVOKER_ROLE, _issuerGov);
        
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256(bytes("VottaCredentialRegistry")),
                keccak256(bytes("1")),
                block.chainid,
                address(this)
            )
        );
    }
    
    /* ========== PUBLIC FUNCTIONS ========== */
    
    /**
     * @notice Issues a new credential to a voter
     * @param idHash Hash of the voter's identification
     * @param voter Address of the voter's wallet
     * @param sigGov Signature from the government issuer
     * @param sigNGO Signature from the NGO issuer
     */
    function issue(
        bytes32 idHash,
        address voter,
        bytes calldata sigGov,
        bytes calldata sigNGO
    ) external {
        // Check that the credential hasn't been issued before
        if (status[idHash] != Status.None) revert AlreadyIssued();
        
        // Create a nonce based on current block timestamp / 1 hour window
        uint256 nonce = block.timestamp / 3600;
        
        // Verify signatures from both issuers
        bytes32 structHash = keccak256(
            abi.encode(
                CREDENTIAL_TYPEHASH,
                idHash,
                voter,
                nonce
            )
        );
        
        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                DOMAIN_SEPARATOR,
                structHash
            )
        );
        
        if (digest.recover(sigGov) != issuerGov) revert InvalidSignatureGov();
        if (digest.recover(sigNGO) != issuerNGO) revert InvalidSignatureNGO();
        
        // Set credential as valid
        status[idHash] = Status.Valid;
        
        // Emit event
        emit CredentialIssued(idHash, voter);
    }
    
    /**
     * @notice Revokes a credential
     * @param idHash Hash of the voter's identification to revoke
     */
    function revoke(bytes32 idHash) external onlyRole(REVOKER_ROLE) {
        // Check that the credential exists and is valid
        if (status[idHash] == Status.None) revert NotValidCredential();
        if (status[idHash] == Status.Revoked) revert AlreadyRevoked();
        
        // Set credential as revoked
        status[idHash] = Status.Revoked;
        
        // Emit event
        emit CredentialRevoked(idHash);
    }
    
    /* ========== VIEW FUNCTIONS ========== */
    
    /**
     * @notice Checks if a credential is valid
     * @param idHash Hash of the voter's identification
     * @return bool True if the credential is valid
     */
    function isValid(bytes32 idHash) external view returns (bool) {
        return status[idHash] == Status.Valid;
    }
    
    /**
     * @notice Gets the status of a credential
     * @param idHash Hash of the voter's identification
     * @return Status The current status of the credential
     */
    function getStatus(bytes32 idHash) external view returns (Status) {
        return status[idHash];
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
