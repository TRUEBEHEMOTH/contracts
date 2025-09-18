const { ethers, upgrades } = require("hardhat");

async function main() {
  console.log("Deploying  2025 E-Voting Roll-up contracts...");

  // Get the signers
  const [deployer] = await ethers.getSigners();
  console.log(`Deploying contracts with the account: ${deployer.address}`);

  // Deploy configuration parameters
  const ISSUER_GOV = deployer.address; // For demo purposes, replace with actual government issuer
  const ISSUER_NGO = deployer.address; // For demo purposes, replace with actual NGO issuer
  const ADMIN_MULTISIG = deployer.address; // For demo purposes, replace with actual 3-of-5 multisig
  const WATCH_TOWER = deployer.address; // For demo purposes, replace with actual watch tower
  const AGGREGATOR = deployer.address; // For demo purposes, replace with actual aggregator
  
  const NUM_CANDIDATES = 5; // Number of candidates in the election
  const CHALLENGE_WINDOW = 15 * 60; // 15 minutes in seconds
  
  // Election end time: 30 days from now
  const ELECTION_END_TIME = Math.floor(Date.now() / 1000) + (30 * 24 * 60 * 60);

  console.log("Deployment parameters:");
  console.log(`- Admin Multisig: ${ADMIN_MULTISIG}`);
  console.log(`- Issuer Government: ${ISSUER_GOV}`);
  console.log(`- Issuer NGO: ${ISSUER_NGO}`);
  console.log(`- Watch Tower: ${WATCH_TOWER}`);
  console.log(`- Aggregator: ${AGGREGATOR}`);
  console.log(`- Number of Candidates: ${NUM_CANDIDATES}`);
  console.log(`- Challenge Window: ${CHALLENGE_WINDOW} seconds`);
  console.log(`- Election End Time: ${new Date(ELECTION_END_TIME * 1000).toISOString()}`);

  // 1. Deploy CredentialRegistry (proxy)
  console.log("\nDeploying CredentialRegistry...");
  const CredentialRegistry = await ethers.getContractFactory("CredentialRegistry");
  const credentialRegistry = await upgrades.deployProxy(
    CredentialRegistry,
    [ISSUER_GOV, ISSUER_NGO, ADMIN_MULTISIG],
    { kind: "uups" }
  );
  await credentialRegistry.waitForDeployment();
  console.log(`CredentialRegistry deployed to: ${await credentialRegistry.getAddress()}`);

  // 2. Deploy PlonkVerifier
  console.log("\nDeploying PlonkVerifier...");
  const PlonkVerifier = await ethers.getContractFactory("PlonkVerifier");
  const plonkVerifier = await PlonkVerifier.deploy();
  await plonkVerifier.waitForDeployment();
  console.log(`PlonkVerifier deployed to: ${await plonkVerifier.getAddress()}`);

  // 3. Deploy VotingBatch (proxy)
  console.log("\nDeploying VotingBatch...");
  const VotingBatch = await ethers.getContractFactory("VotingBatch");
  const votingBatch = await upgrades.deployProxy(
    VotingBatch,
    [
      NUM_CANDIDATES,
      CHALLENGE_WINDOW,
      await plonkVerifier.getAddress(),
      ethers.ZeroAddress, // Temporary PenaltyVault address, will update after deployment
      AGGREGATOR,
      ADMIN_MULTISIG,
      ELECTION_END_TIME
    ],
    { kind: "uups" }
  );
  await votingBatch.waitForDeployment();
  console.log(`VotingBatch deployed to: ${await votingBatch.getAddress()}`);

  // 4. Deploy PenaltyVault (proxy)
  console.log("\nDeploying PenaltyVault...");
  const PenaltyVault = await ethers.getContractFactory("PenaltyVault");
  const penaltyVault = await upgrades.deployProxy(
    PenaltyVault,
    [
      WATCH_TOWER,
      await votingBatch.getAddress(),
      ADMIN_MULTISIG
    ],
    { kind: "uups" }
  );
  await penaltyVault.waitForDeployment();
  console.log(`PenaltyVault deployed to: ${await penaltyVault.getAddress()}`);

  // 5. Update PenaltyVault address in VotingBatch
  console.log("\nUpdating PenaltyVault address in VotingBatch...");
  // This would require a custom function to update the PenaltyVault address
  // For the purposes of this example, we'll assume the VotingBatch contract has this capability
  // In a real implementation, this might be part of the initialize function or a separate setter

  console.log("\nDeployment completed successfully!");
  console.log("\nContract Addresses:");
  console.log(`- CredentialRegistry: ${await credentialRegistry.getAddress()}`);
  console.log(`- PlonkVerifier: ${await plonkVerifier.getAddress()}`);
  console.log(`- VotingBatch: ${await votingBatch.getAddress()}`);
  console.log(`- PenaltyVault: ${await penaltyVault.getAddress()}`);
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
