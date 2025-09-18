const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

// BN254 Field size
const FIELD_SIZE = BigInt("21888242871839275222246405745257275088696311157297823662689037894645226208583");

/**
 * Generate test proof values that will pass the basic validation
 * in our PlonkVerifier contract when testMode is enabled
 */
function main() {
  console.log("Generating compatible test proof values...");
  
  // Generate the proof
  const { proof, publicInputs } = generateTestProof();
  
  // Save the values to a test file
  const testFilePath = path.join(__dirname, "..", "test", "test-proof.js");
  
  const testFileContent = `// Auto-generated test proof values
// These values are designed to pass the test mode validation in the PLONK verifier
module.exports = {
  // Proof in serialized format (768 bytes / 24 x 32-byte elements)
  proofHex: "${proof}",
  
  // Public inputs (2 elements - merkleRoot and countsHash)
  publicInputs: [
    "${publicInputs[0]}",
    "${publicInputs[1]}"
  ]
};
`;
  
  fs.writeFileSync(testFilePath, testFileContent);
  console.log(`Test proof values generated and saved to ${testFilePath}`);
}

/**
 * Generates test proof values that will pass validation
 */
function generateTestProof() {
  // Generate random values for public inputs (within field size)
  const publicInputs = [
    randomFieldElement(),
    randomFieldElement()
  ];
  
  // Create arrays for curve points - each point is (x,y)
  const A = [randomFieldElement(), randomFieldElement()];
  const B = [randomFieldElement(), randomFieldElement()];
  const C = [randomFieldElement(), randomFieldElement()];
  const Z = [randomFieldElement(), randomFieldElement()];
  
  // Create opening proof commitments
  const W_z = [randomFieldElement(), randomFieldElement()];
  const W_zw = [randomFieldElement(), randomFieldElement()];
  
  // Create scalar values
  const t = randomFieldElement();
  const r = randomFieldElement();
  const a = randomFieldElement();
  const b = randomFieldElement();
  const c = randomFieldElement();
  const z_omega = randomFieldElement();
  
  // Serialize the proof into a single hex string (24 elements total)
  const proofElements = [
    // G1 points as (x,y) pairs: A, B, C, Z (8 elements)
    ...A, ...B, ...C, ...Z,
    
    // Scalar values: t, r, a, b, c, z_omega (6 elements)
    t, r, a, b, c, z_omega,
    
    // Opening proof commitments: W_z, W_zw (4 elements)
    ...W_z, ...W_zw
  ];
  
  // Convert all values to hex and pad to 32 bytes
  const proofHex = "0x" + proofElements.map(e => 
    e.toString(16).padStart(64, '0')
  ).join('');
  
  return {
    proof: proofHex,
    publicInputs: publicInputs.map(pi => "0x" + pi.toString(16).padStart(64, '0'))
  };
}

/**
 * Generates a random value in the BN254 field
 */
function randomFieldElement() {
  // Generate 30 random bytes (240 bits) to ensure it's < field size
  const randomBytes = crypto.randomBytes(30);
  // Convert to BigInt and ensure it's within field size
  const value = BigInt('0x' + randomBytes.toString('hex')) % FIELD_SIZE;
  return value;
}

// Run the script
try {
  main();
} catch (error) {
  console.error(error);
  process.exit(1);
}
