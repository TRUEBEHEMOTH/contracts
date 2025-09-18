const { expect } = require("chai");
const { ethers, upgrades } = require("hardhat");
const { time } = require("@nomicfoundation/hardhat-network-helpers");

describe("VotingBatch", function () {
  // Test variables
  let VotingBatch;
  let votingBatch;
  let PlonkVerifier;
  let verifier;
  let PenaltyVault;
  let penaltyVault;
  let owner;
  let aggregator;
  let watchTower;
  let voter1;
  let voter2;
  
  // Constants
  const ZERO_ADDRESS = ethers.ZeroAddress;
  const AGGREGATOR_ROLE = ethers.keccak256(ethers.toUtf8Bytes("AGGREGATOR_ROLE"));
  const WATCHTOWER_ROLE = ethers.keccak256(ethers.toUtf8Bytes("WATCHTOWER_ROLE"));
  const CHALLENGE_WINDOW = 3600 * 24; // 1 day
  const BOND_AMOUNT = ethers.parseEther("1");
  
  beforeEach(async function () {
    // Get signers
    [owner, aggregator, watchTower, voter1, voter2] = await ethers.getSigners();
    
    // Use the real PlonkVerifier with testMode enabled
    PlonkVerifier = await ethers.getContractFactory("PlonkVerifier");
    verifier = await PlonkVerifier.deploy();
    // Wait for the deployment transaction to be mined
    await verifier.deploymentTransaction().wait();
    console.log("Mock Verifier deployed at:", verifier.target);
    
    // Deploy PenaltyVault using proxy pattern for proper initialization
    PenaltyVault = await ethers.getContractFactory("PenaltyVault");
    penaltyVault = await upgrades.deployProxy(PenaltyVault, [
      watchTower.address, // _watchTower
      ethers.ZeroAddress,  // _votingBatch (we'll update this after VotingBatch is deployed)
      owner.address        // _admin
    ]);
    console.log("PenaltyVault deployed at:", penaltyVault.target);
    
    // Deploy VotingBatch using proxy
    VotingBatch = await ethers.getContractFactory("VotingBatch");
    
    // Current timestamp
    const currentTime = Math.floor(Date.now() / 1000);
    // Election end time (1 day from now)
    const electionEndTime = currentTime + 86400;
    // Create a test poll ID
    const testPollId = ethers.keccak256(ethers.toUtf8Bytes("test_poll"));
    
    // Initialize with all 8 required parameters
    votingBatch = await upgrades.deployProxy(VotingBatch, [
      3, // _numCandidates: 3 candidates in the election
      CHALLENGE_WINDOW, // _challengeWindow: Time window for challenges
      verifier.target, // _verifier: Address of the verifier contract
      penaltyVault.target, // _penaltyVault: Address of the penalty vault
      aggregator.address, // _aggregator: Address of the aggregator
      owner.address, // _admin: Address of the admin
      electionEndTime, // _electionEndTime: Timestamp when the election ends
      testPollId // _pollId: Unique identifier for this poll
    ]);
    // No need to call deployed() in ethers v6
    
    // Grant roles
    await votingBatch.grantRole(AGGREGATOR_ROLE, aggregator.address);
    await votingBatch.grantRole(WATCHTOWER_ROLE, watchTower.address);
    
    // Grant WATCHTOWER_ROLE in PenaltyVault to VotingBatch contract to allow slashing
    await penaltyVault.grantRole(WATCHTOWER_ROLE, votingBatch.target);
    
    // Deposit stake for the aggregator to allow slashing during challenges
    // The SLASH_AMOUNT in the VotingBatch contract is 100 ETH
    await penaltyVault.connect(aggregator).deposit({ value: ethers.parseEther("100") });
  });
  
  describe("Deployment", function () {
    it("Should set the right owner", async function () {
      const defaultAdminRole = ethers.ZeroHash;
      expect(await votingBatch.hasRole(defaultAdminRole, owner.address)).to.equal(true);
    });
    
    it("Should set the correct verifier and penalty vault addresses", async function () {
      expect(await votingBatch.plonkVerifier()).to.equal(verifier.target);
      expect(await votingBatch.penaltyVault()).to.equal(penaltyVault.target);
    });
    
    // Skip bond amount test - there is no BOND_AMOUNT public variable in the contract
    // In a real test, we would check for the actual state variable or effect
    
    it("Should grant AGGREGATOR_ROLE to the correct address", async function () {
      expect(await votingBatch.hasRole(AGGREGATOR_ROLE, aggregator.address)).to.equal(true);
    });
    
    it("Should grant WATCHTOWER_ROLE to the correct address", async function () {
      expect(await votingBatch.hasRole(WATCHTOWER_ROLE, watchTower.address)).to.equal(true);
    });
  });
  
  // Create a valid proof for testing that will pass the verifier's checks
  function createValidProof() {
    // Create 8 32-byte chunks, each containing a small value
    let proofParts = [];
    for (let i = 0; i < 8; i++) {
      let smallValue = new Uint8Array(32);
      smallValue[31] = i + 1; // Use different small values for each chunk
      proofParts.push(ethers.hexlify(smallValue));
    }
    // Add padding to reach the required 768 bytes
    if (768 > 8 * 32) {
      proofParts.push(ethers.hexlify(ethers.randomBytes(768 - 8 * 32)));
    }
    return ethers.concat(proofParts);
  }

  describe("Batch Submission", function () {
    // In VotingBatch, we're using the batch id as the poll id (see line 172 in VotingBatch.sol)
    let batchId = 1; // This will be our id parameter (uint64)
    let merkleRoot = ethers.keccak256(ethers.toUtf8Bytes("merkle_root")); // This will be our root parameter (bytes32)
    let counts = [10, 20, 30]; // Votes for each candidate - counts parameter (uint256[])
    
    // Create a proof that will pass the PlonkVerifier's checks
    // Generate a proof with 8 specific 32-byte chunks followed by padding
    function createValidProof() {
      // Create 8 32-byte chunks, each containing a number less than FIELD_SIZE
      let proofParts = [];
      for (let i = 0; i < 8; i++) {
        // Create a byte array with 31 bytes of zeros and 1 byte with a small value
        // This ensures the number will be well below FIELD_SIZE
        let smallValue = new Uint8Array(32);
        smallValue[31] = i + 1; // Just set the lowest byte to a small value
        proofParts.push(ethers.hexlify(smallValue));
      }
      
      // Rest of the proof can be random (for the full 768 bytes)
      if (768 > 8 * 32) {
        proofParts.push(ethers.hexlify(ethers.randomBytes(768 - 8 * 32)));
      }
      
      return ethers.concat(proofParts);
    }
    
    let validProof = createValidProof(); // proof parameter (bytes)
    
    it("Should allow an aggregator to submit a batch", async function () {
      await expect(
        votingBatch.connect(aggregator).submitBatch(
          batchId, // id parameter
          merkleRoot, // root parameter
          counts, // counts parameter
          validProof // proof parameter
        )
      )
        .to.emit(votingBatch, "BatchSubmitted")
        .withArgs(batchId, merkleRoot, counts);
      
      // Check the batch was stored correctly
      const batch = await votingBatch.batches(batchId);
      expect(batch.pollId).to.equal(batchId);
      expect(batch.root).to.equal(merkleRoot);
      
      // Check if vote counts were updated
      for (let i = 0; i < counts.length; i++) {
        expect(await votingBatch.candidateVotes(i)).to.equal(counts[i]);
      }
    });
    
    it("Should not allow non-aggregators to submit a batch", async function () {
      await expect(
        votingBatch.connect(watchTower).submitBatch(
          batchId,
          merkleRoot,
          counts,
          validProof
        )
      ).to.be.reverted;
    });
    
    it("Should not allow submitting a batch with the same ID twice", async function () {
      // Submit first batch
      await votingBatch.connect(aggregator).submitBatch(
        batchId,
        merkleRoot,
        counts,
        validProof
      );
      
      // Try to submit another batch with same ID (should fail)
      await expect(
        votingBatch.connect(aggregator).submitBatch(
          batchId,
          merkleRoot,
          counts,
          validProof
        )
      ).to.be.revertedWithCustomError(votingBatch, "DuplicateBatch");
    });
  });
  
  describe("Challenge Mechanism", function () {
    let pollId = 1;
    let batchId = 1;
    let merkleRoot = ethers.keccak256(ethers.toUtf8Bytes("merkle_root"));
    let counts = [10, 20, 30]; // Votes for each candidate
    let validProof = ethers.hexlify(ethers.randomBytes(768));
    
    beforeEach(async function () {
      // Submit a batch first
      await votingBatch.connect(aggregator).submitBatch(
        batchId,
        merkleRoot,
        counts,
        validProof
      );
      
      // Fund watchTower with bond amount
      await owner.sendTransaction({
        to: watchTower.address,
        value: ethers.parseEther("2") // Use a fixed amount for testing
      });
    });
    
    it("Should allow challenging a batch with valid duplicate credential evidence", async function () {
      // Create Type 1 evidence (Duplicate credential)
      // [type=1][32-byte receipt1][32-byte receipt2]
      const receipt1 = ethers.hexlify(ethers.randomBytes(32));
      const receipt2 = ethers.hexlify(ethers.randomBytes(32));
      
      // Format the evidence
      const evidenceType = "0x01"; // Type 1
      const evidence = ethers.concat([
        evidenceType,
        receipt1,
        receipt2
      ]);
      
      // Submit challenge
      await expect(
        votingBatch.connect(watchTower).challenge(batchId, evidence, {
          value: BOND_AMOUNT
        })
      )
        .to.emit(votingBatch, "BatchChallenged")
        .withArgs(batchId);
      
      // Batch should be marked as challenged
      expect(await votingBatch.challenged(batchId)).to.equal(true);
    });
    
    it("Should allow challenging a batch with valid invalid signature evidence", async function () {
      // Create Type 2 evidence (Invalid signature)
      // [type=2][32-byte credentialHash][65-byte signature][32-byte messageHash]
      const credentialHash = ethers.hexlify(ethers.randomBytes(32));
      const signature = ethers.hexlify(ethers.randomBytes(65));
      const messageHash = ethers.hexlify(ethers.randomBytes(32));
      
      // Format the evidence
      const evidenceType = "0x02"; // Type 2
      const evidence = ethers.concat([
        evidenceType,
        credentialHash,
        signature,
        messageHash
      ]);
      
      // Submit challenge
      await expect(
        votingBatch.connect(watchTower).challenge(batchId, evidence, {
          value: BOND_AMOUNT
        })
      )
        .to.emit(votingBatch, "BatchChallenged")
        .withArgs(batchId);
      
      // Batch should be marked as challenged
      expect(await votingBatch.challenged(batchId)).to.equal(true);
    });
    
    it("Should allow challenging a batch with valid root inconsistency evidence", async function () {
      // Create Type 3 evidence (Root inconsistency)
      // From the contract's _verifyChallenge implementation for Type 3:
      // - Format: [type=3][32-byte actualRoot][32-byte claimedRoot]
      // - It extracts claimedRoot at position 33 (after the type byte)
      // - It checks if batch.root != claimedRoot for validation
      // - To make this pass, the extracted claimedRoot must be different from the actual batch.root
      
      // Create fake roots for evidence
      const fakeMerkleRoot = ethers.hexlify(ethers.randomBytes(32)); // A fake root different from what was submitted
      
      // Format the evidence so validation passes: batch.root != claimedRoot must be true
      const evidenceType = "0x03"; // Type 3
      const evidence = ethers.concat([
        evidenceType,
        ethers.ZeroHash, // First 32 bytes (not used by contract)
        fakeMerkleRoot  // This is extracted as claimedRoot and must differ from batch.root
      ]);
      
      // Submit challenge
      await expect(
        votingBatch.connect(watchTower).challenge(batchId, evidence, {
          value: BOND_AMOUNT
        })
      )
        .to.emit(votingBatch, "BatchChallenged")
        .withArgs(batchId);
      
      // Batch should be marked as challenged
      expect(await votingBatch.challenged(batchId)).to.equal(true);
    });
    
    it("Should reject challenge with invalid evidence format", async function () {
      // Create invalid evidence (too short)
      const evidence = "0x01"; // Just the type byte
      
      // Submit challenge
      await expect(
        votingBatch.connect(watchTower).challenge(batchId, evidence, {
          value: BOND_AMOUNT
        })
      ).to.be.revertedWithCustomError(votingBatch, "InvalidChallenge");
    });
    
    it("Should reject challenge with unsupported evidence type", async function () {
      // Create evidence with unsupported type
      const evidenceType = "0x04"; // Type 4 (not supported)
      const dummyData = ethers.hexlify(ethers.randomBytes(64));
      const evidence = ethers.concat([evidenceType, dummyData]);
      
      // Submit challenge
      await expect(
        votingBatch.connect(watchTower).challenge(batchId, evidence, {
          value: BOND_AMOUNT
        })
      ).to.be.revertedWithCustomError(votingBatch, "InvalidChallenge");
    });
    
    it("Should reject challenge after challenge window expires", async function () {
      // Move time forward past the challenge window
      await time.increase(CHALLENGE_WINDOW + 1);
      
      // Create valid evidence
      const evidenceType = "0x01"; // Type 1
      const receipt1 = ethers.hexlify(ethers.randomBytes(32));
      const receipt2 = ethers.hexlify(ethers.randomBytes(32));
      const evidence = ethers.concat([evidenceType, receipt1, receipt2]);
      
      // Submit challenge
      await expect(
        votingBatch.connect(watchTower).challenge(batchId, evidence, {
          value: BOND_AMOUNT
        })
      ).to.be.revertedWithCustomError(votingBatch, "ChallengeWindowExpired");
    });
    
    it("Should reject challenge with insufficient bond", async function () {
      // Create valid evidence
      const evidenceType = "0x01"; // Type 1
      const receipt1 = ethers.hexlify(ethers.randomBytes(32));
      const receipt2 = ethers.hexlify(ethers.randomBytes(32));
      const evidence = ethers.concat([evidenceType, receipt1, receipt2]);
      
      // Submit challenge with insufficient bond
      await expect(
        votingBatch.connect(watchTower).challenge(batchId, evidence, {
          value: ethers.parseEther("0.5") // Half of the 1 ETH bond amount
        })
      ).to.be.revertedWithCustomError(votingBatch, "InsufficientBond");
    });
  });
  
  describe("Recover Bond", function () {
    let pollId = 1;
    let batchId = 1;
    let merkleRoot = ethers.keccak256(ethers.toUtf8Bytes("merkle_root"));
    let counts = [10, 20, 30]; // Votes for each candidate
    let validProof = ethers.hexlify(ethers.randomBytes(768));
    let evidence;
    
    beforeEach(async function () {
      // Submit a batch
      await votingBatch.connect(aggregator).submitBatch(
        batchId,
        merkleRoot,
        counts,
        validProof
      );
      
      // Fund watchTower with bond amount
      await owner.sendTransaction({
        to: watchTower.address,
        value: ethers.parseEther("2") // Use a fixed amount for testing
      });
      
      // Create Type 1 evidence
      const evidenceType = "0x01"; // Type 1
      const receipt1 = ethers.hexlify(ethers.randomBytes(32));
      const receipt2 = ethers.hexlify(ethers.randomBytes(32));
      evidence = ethers.concat([evidenceType, receipt1, receipt2]);
      
      // Submit challenge
      await votingBatch.connect(watchTower).challenge(batchId, evidence, {
        value: BOND_AMOUNT
      });
    });
    
    it("Should allow watchTower to recover bond after challenge window", async function () {
      // Move time forward past the challenge window
      await time.increase(CHALLENGE_WINDOW + 1);
      
      const initialBalance = await ethers.provider.getBalance(watchTower.address);
      
      // Recover bond
      await votingBatch.connect(watchTower).recoverBond(batchId);
      
      const finalBalance = await ethers.provider.getBalance(watchTower.address);
      
      // Account for gas costs, the balance should have increased by approximately BOND_AMOUNT
      expect(finalBalance).to.be.gt(initialBalance);
    });
    
    it("Should not allow recovering bond before challenge window ends", async function () {
      // Try to recover bond before challenge window
      await expect(
        votingBatch.connect(watchTower).recoverBond(batchId)
      ).to.be.revertedWithCustomError(votingBatch, "ChallengeWindowActive");
    });
    
    it("Should not allow non-challenger to recover bond", async function () {
      // Move time forward past the challenge window
      await time.increase(CHALLENGE_WINDOW + 1);
      
      // Try to recover bond as non-challenger
      await expect(
        votingBatch.connect(voter1).recoverBond(batchId)
      ).to.be.revertedWithCustomError(votingBatch, "NotChallenger");
    });
    
    it("Should not allow recovering bond twice", async function () {
      // Move time forward past the challenge window
      await time.increase(CHALLENGE_WINDOW + 1);
      
      // Recover bond first time
      await votingBatch.connect(watchTower).recoverBond(batchId);
      
      // Try to recover bond second time
      await expect(
        votingBatch.connect(watchTower).recoverBond(batchId)
      ).to.be.revertedWithCustomError(votingBatch, "BondAlreadyRecovered");
    });
  });
  
  describe("Get Total Votes", function () {
    let batchIds = [1, 2, 3];
    let merkleRoot = ethers.keccak256(ethers.toUtf8Bytes("merkle_root"));
    let counts = [10, 20, 30]; // Votes for each candidate
    let validProof = createValidProof(); // proof parameter (bytes)
    
    beforeEach(async function () {
      // Submit multiple batches for the same poll
      for (let i = 0; i < batchIds.length; i++) {
        await votingBatch.connect(aggregator).submitBatch(
          batchIds[i],
          merkleRoot,
          counts,
          validProof
        );
      }
    });
    
    it("Should return the correct total votes across all candidates", async function () {
      const totalVotes = await votingBatch.getTotalVotes();
      
      // Expected total votes across all candidates and batches
      const expectedTotal = counts.reduce((sum, count) => sum + count, 0) * batchIds.length;
      
      // Check total votes match expected value
      expect(totalVotes).to.equal(expectedTotal);
      
      // Check individual candidate votes
      for (let i = 0; i < counts.length; i++) {
        const candidateVote = await votingBatch.candidateVotes(i);
        expect(candidateVote).to.equal(counts[i] * batchIds.length);
      }
    });
  });
});
