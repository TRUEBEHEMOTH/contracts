// Script to generate a PLONK verifier contract using circom and snarkjs
const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

// Ensure the necessary directories exist
const circuitsDir = path.join(__dirname, '..', 'circuits');
const buildDir = path.join(circuitsDir, 'build');

// Create directories if they don't exist
if (!fs.existsSync(circuitsDir)) fs.mkdirSync(circuitsDir);
if (!fs.existsSync(buildDir)) fs.mkdirSync(buildDir);

// Step 1: Create a simple circuit file for demonstration
// In production, you would replace this with your actual voting circuit
console.log('Creating circuit file...');
const circuitPath = path.join(circuitsDir, 'voting_circuit.circom');
const circuitContent = `
pragma circom 2.0.0;

// Simple circuit to verify that merkle_root corresponds to the provided votes
// This is just a demonstration - your real circuit would be more complex
template VotingVerification() {
    // Public inputs
    signal input merkle_root;
    signal input counts_hash;
    
    // Private inputs (would include vote data, proofs, etc.)
    signal input vote_data;
    signal input secret_key;
    
    // Simple constraint to demonstrate the concept
    // In reality, this would include merkle proof verification,
    // vote counting logic, etc.
    signal output valid_batch;
    
    // Add constraints (simplified for demonstration)
    valid_batch <== merkle_root * counts_hash - vote_data * secret_key;
}

component main = VotingVerification();
`;
fs.writeFileSync(circuitPath, circuitContent);
console.log('Circuit file created.');

// Step 2: Install dependencies if needed (in a real script, you'd check and install)
console.log('Please ensure you have installed the following dependencies:');
console.log('- circom (npm install -g circom)');
console.log('- snarkjs (npm install -g snarkjs)');

// Step 3: Detailed instructions for generating the verifier
console.log('\nTo generate the PLONK verifier contract, execute these commands:');
console.log('\n# 1. Compile the circuit');
console.log(`circom ${circuitPath} --r1cs --wasm --sym -o ${buildDir}`);

console.log('\n# 2. Generate a PLONK trusted setup (in production use a proper ceremony)');
console.log(`cd ${buildDir} && snarkjs plonk setup voting_circuit.r1cs pot12_final.ptau voting_circuit.zkey`);

console.log('\n# 3. Export the verification key');
console.log(`cd ${buildDir} && snarkjs zkey export verificationkey voting_circuit.zkey verification_key.json`);

console.log('\n# 4. Generate the Solidity verifier contract');
console.log(`cd ${buildDir} && snarkjs zkey export solidityverifier voting_circuit.zkey PlonkVerifier.sol`);

console.log('\n# 5. Copy the generated verifier to the contracts directory');
console.log(`cp ${buildDir}/PlonkVerifier.sol ${path.join(__dirname, '..', 'contracts', 'PlonkVerifier.sol')}`);

console.log('\n# Note: For a full production setup, you should:');
console.log('1. Create a more complex circuit that verifies vote validity');
console.log('2. Participate in or create a secure trusted setup (Powers of Tau ceremony)');
console.log('3. Thoroughly test the generated verifier');

// Step 4: Generate an example input file for testing
const inputPath = path.join(buildDir, 'input.json');
const inputContent = {
  "merkle_root": "123456789",
  "counts_hash": "987654321",
  "vote_data": "111222333",
  "secret_key": "444555666"
};
fs.writeFileSync(inputPath, JSON.stringify(inputContent, null, 2));
console.log(`\nExample input file created at: ${inputPath}`);

// Step 5: Generate a script to run all commands in sequence
const runScriptPath = path.join(__dirname, 'run-full-generation.sh');
const runScriptContent = `#!/bin/bash
# Full script to generate the PLONK verifier contract
set -e

# Navigate to project root
cd "$(dirname "$0")/.."

# Check for required tools
if ! command -v circom &> /dev/null; then
    echo "circom not found. Please install with: npm install -g circom"
    exit 1
fi

if ! command -v snarkjs &> /dev/null; then
    echo "snarkjs not found. Please install with: npm install -g snarkjs"
    exit 1
fi

# Step 1: Download Powers of Tau file if needed
if [ ! -f "./circuits/build/pot12_final.ptau" ]; then
    echo "Downloading Powers of Tau file..."
    mkdir -p ./circuits/build
    curl -L https://hermez.s3-eu-west-1.amazonaws.com/powersOfTau28_hez_final_12.ptau -o ./circuits/build/pot12_final.ptau
fi

# Step 2: Compile the circuit
echo "Compiling the circuit..."
circom ./circuits/voting_circuit.circom --r1cs --wasm --sym -o ./circuits/build

# Step 3: Generate the zkey file
echo "Generating the zkey file..."
cd ./circuits/build
snarkjs plonk setup voting_circuit.r1cs pot12_final.ptau voting_circuit.zkey

# Step 4: Export the verification key
echo "Exporting the verification key..."
snarkjs zkey export verificationkey voting_circuit.zkey verification_key.json

# Step 5: Generate the Solidity verifier
echo "Generating the Solidity verifier..."
snarkjs zkey export solidityverifier voting_circuit.zkey PlonkVerifier.sol

# Step 6: Copy the verifier to the contracts directory
echo "Copying the verifier to the contracts directory..."
cp PlonkVerifier.sol ../../contracts/

# Step 7: Generate a test proof (optional)
echo "Generating a test proof..."
node ./voting_circuit_js/generate_witness.js ./voting_circuit_js/voting_circuit.wasm ../input.json witness.wtns
snarkjs plonk prove voting_circuit.zkey witness.wtns proof.json public.json

# Step 8: Verify the proof (optional)
echo "Verifying the test proof..."
snarkjs plonk verify verification_key.json public.json proof.json

echo "Done! The PlonkVerifier contract has been generated and placed in the contracts directory."
`;
fs.writeFileSync(runScriptPath, runScriptContent);
console.log(`\nFull generation script created at: ${runScriptPath}`);
console.log('To run it: bash scripts/run-full-generation.sh');

// Make the script executable
try {
  execSync(`chmod +x ${runScriptPath}`);
  console.log('Script made executable.');
} catch (error) {
  console.log('Could not make script executable. You may need to run: chmod +x scripts/run-full-generation.sh');
}

console.log('\nIMPORTANT: For a production voting system, you will need:');
console.log('1. A proper circuit that validates your specific voting logic');
console.log('2. A secure trusted setup process');
console.log('3. Integration tests between your VotingBatch contract and the generated PlonkVerifier');
