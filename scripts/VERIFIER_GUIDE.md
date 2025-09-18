# Votta PLONK Verifier Generation Guide

This guide explains how to generate a production-ready PLONK verifier for the Votta E-Voting system.

## Prerequisites

Before running the script, make sure you have installed:

- Node.js (v14 or higher)
- circom (v2.0.0 or higher): `npm install -g circom`
- snarkjs: `npm install -g snarkjs`

## Getting Started

1. Install the required NPM packages:

```bash
npm install snarkjs circom
```

2. Run the generation script:

```bash
node scripts/generate-verifier.js
```

This will create:
- A sample circuit in `circuits/voting_circuit.circom`
- A bash script to run the full generation process

3. Execute the full generation script:

```bash
bash scripts/run-full-generation.sh
```

This will:
- Download the Powers of Tau file (if needed)
- Compile the circuit
- Generate the zkey file
- Export the verification key
- Generate a production-ready Solidity PlonkVerifier contract
- Copy the verifier to the contracts directory
- Generate and verify a test proof

## Creating a Production Circuit

For a real voting system, you'll need to replace the sample circuit with one that properly validates:

1. **Vote Structure**: Ensure votes are well-formed
2. **Merkle Tree Proofs**: Verify votes are included in the batch's merkle tree
3. **Vote Counting**: Verify the vote counts match the claimed totals
4. **Credential Uniqueness**: Ensure each credential is only used once
5. **Signature Verification**: Verify that votes are properly signed

## Integration with VotingBatch

The generated PlonkVerifier contract will expose a `verify(bytes calldata proof, bytes32[] calldata pubInputs)` function that your VotingBatch contract can call.

Example usage in VotingBatch:

```solidity
// In submitBatch function
bytes32[] memory pubInputs = new bytes32[](2);
pubInputs[0] = root;
pubInputs[1] = countsHash;

if (!plonkVerifier.verify(proof, pubInputs)) revert BadProof();
```

## Security Considerations

1. **Trusted Setup**: For maximum security, participate in a proper Powers of Tau ceremony
2. **Circuit Auditing**: Have cryptography experts review your circuit design
3. **Gas Optimization**: PLONK verification is gas-intensive; consider layer 2 solutions
4. **Testing**: Thoroughly test the generated verifier with both valid and invalid proofs

## Advanced Topics

- **Batched Verification**: If processing multiple batches, consider optimizing by implementing batched verification
- **Upgradeability**: Use proxy patterns to allow upgrading the verifier if cryptographic vulnerabilities are discovered
- **Security Adjustments**: Consider the security vs. gas usage tradeoff when designing your circuit

## Resources

- [Circom Documentation](https://docs.circom.io/)
- [snarkjs Documentation](https://github.com/iden3/snarkjs)
- [PLONK Paper](https://eprint.iacr.org/2019/953)
- [ZK-SNARK Explainer](https://vitalik.ca/general/2016/12/10/qap.html)
