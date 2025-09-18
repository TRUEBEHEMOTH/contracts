# Votta E-Voting System

![Votta](https://via.placeholder.com/150?text=Votta)

A secure, transparent, and decentralized electronic voting system built on blockchain technology with zero-knowledge proofs.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

## Table of Contents

- [Overview](#overview)
- [System Architecture](#system-architecture)
- [Smart Contracts](#smart-contracts)
- [Off-Chain Services](#off-chain-services)
- [Installation](#installation)
- [Usage Guide](#usage-guide)
  - [Running the System](#running-the-system)
  - [Configuration](#configuration)
  - [Monitoring](#monitoring)
- [Development](#development)
  - [Testing](#testing)
  - [Deployment](#deployment)
- [Security](#security)
- [FAQ](#faq)
- [Contributing](#contributing)
- [License](#license)

## Overview

Votta is a next-generation e-voting system designed to provide unparalleled security, transparency, and user privacy. Built on blockchain technology with zero-knowledge proofs, it enables secure and auditable voting while maintaining voter anonymity.

### Key Features

- **Multiple Voting Polls**: Support for running multiple elections simultaneously
- **Credential-Based Voting**: Secure voter registration with cryptographic credentials
- **Batch Processing**: Efficient aggregation of votes into verifiable batches
- **Zero-Knowledge Proofs**: Privacy-preserving vote verification
- **Challenge Mechanism**: Security monitoring and fraud detection
- **Gas-Optimized**: Subsidized transaction costs for voters
- **Decentralized Governance**: Protocol-level management of system components

## System Architecture

The Votta e-voting system consists of several interconnected components:


1. **Smart Contracts**: Core blockchain components handling voting logic, credential management, and batch processing
2. **Aggregator Service**: Off-chain service that collects voting receipts and submits them as batches
3. **Watch-Tower Service**: Security monitoring service that challenges fraudulent batches
4. **ZK-Prover**: Zero-knowledge proof generation and verification service
5. **User Interface**: Web and mobile interfaces for voter interaction

## Smart Contracts

The system includes the following smart contracts:

- **VottaProtocol**: Central management contract that coordinates all other components
- **CredentialRegistry**: Manages voter credentials and verifies eligibility
- **VotingBatch**: Processes batched votes and handles challenges
- **PenaltyVault**: Holds bonds and manages slashing for malicious actors
- **VotingFactory**: Creates and manages voting polls
- **VotingPaymaster**: Covers gas costs for voting operations
- **PlonkVerifier**: Verifies zero-knowledge proofs for batched votes
- **AAValidate**: Validates user operations using account abstraction

## Off-Chain Services

### Aggregator Service

The Aggregator Service, written in Rust, is responsible for:

- Collecting voting receipts from users
- Building Merkle trees of receipt hashes
- Generating zero-knowledge proofs
- Submitting batches to the VotingBatch contract

### Watch-Tower Service

The Watch-Tower Service, written in Go, performs security monitoring:

- Monitors chain events for new batch submissions
- Verifies batch validity and detects fraud
- Challenges fraudulent batches with evidence
- Acts as a security backstop for the system

### ZK-Prover Integration

The ZK-Prover component:

- Generates zero-knowledge proofs for vote batches
- Ensures vote counts match the claimed receipts
- Preserves privacy while enabling verification

## Installation

### Prerequisites

- Node.js v16+ and npm
- Go v1.18+
- Rust v1.65+
- Solidity v0.8.24+
- Hardhat

### Installing Dependencies

#### Smart Contracts

```bash
# Install JavaScript dependencies
npm install

# Install Solidity dependencies
npm install @openzeppelin/contracts @openzeppelin/contracts-upgradeable
```

#### Watch-Tower Service

```bash
cd services/watchtower
go mod download
```

#### Aggregator Service

```bash
cd services/aggregator
cargo build --release
```

## Usage Guide

### Running the System

#### Option 1: Native Execution

1. **Start Local Blockchain**

```bash
npx hardhat node
```

2. **Deploy Smart Contracts**

```bash
npx hardhat run scripts/deploy.js --network localhost
```

3. **Start Aggregator Service**

```bash
cd services/aggregator
cargo run --release -- --config config.toml
```

4. **Start Watch-Tower Service**

```bash
cd services/watchtower
go run main.go
```

#### Option 2: Docker Containers

We provide Docker containers for both the Aggregator and Watch-Tower services to simplify deployment and ensure consistent environments.

1. **Build and Start Services with Docker Compose**

```bash
# From the project root directory
docker-compose up -d
```

This will start both services as defined in the `docker-compose.yml` file.

2. **View Service Logs**

```bash
# View logs for all services
docker-compose logs -f

# View logs for a specific service
docker-compose logs -f watchtower
docker-compose logs -f aggregator
```

3. **Stop Services**

```bash
docker-compose down
```

4. **Rebuilding After Code Changes**

```bash
docker-compose up -d --build
```

#### Docker Container Details

**Watch-Tower Container**
- Image: Based on Go 1.21 Alpine
- Ports: 3001 (API and metrics)
- Volumes: Persistent data stored in Docker volume `watchtower-data`
- Configuration: Uses environment variables from `.env` file

**Aggregator Container**
- Image: Based on Rust 1.73
- Ports: 3000 (API), 9090 (metrics)
- Volumes: Persistent data stored in Docker volume `aggregator-data`
- Configuration: Uses environment variables from `.env` file

### Configuration

All services can be configured through environment variables using a `.env` file. Copy the provided `.env.example` to `.env` and adjust the values as needed:

```bash
cp .env.example .env
```

Key configuration parameters include:

- Ethereum RPC endpoints
- Contract addresses
- Service settings
- Security parameters

### Monitoring

The system provides monitoring endpoints for both services:

- **Aggregator API**: http://localhost:3000/metrics
- **Watch-Tower API**: http://localhost:3001/metrics

## Development

### Testing

#### Smart Contracts

```bash
npx hardhat test
```

#### Watch-Tower Service

```bash
cd services/watchtower
go test ./...
```

#### Aggregator Service

```bash
cd services/aggregator
cargo test
```

### Deployment

The project supports deployment to various networks:

```bash
# Goerli Testnet
npx hardhat run scripts/deploy.js --network goerli

# Mainnet
npx hardhat run scripts/deploy.js --network mainnet
```

## Security

The Votta e-voting system incorporates multiple security layers:

1. **Zero-Knowledge Proofs**: Ensures vote privacy while enabling verification
2. **Challenge Mechanism**: Allows detection and penalization of fraud
3. **Bonded Operators**: Economic incentives for honest behavior
4. **Multiple Signatures**: Requires multiple authorities to issue credentials
5. **Time Delays**: Challenge windows for detecting and addressing issues

## FAQ

### General Questions

**Q: How does Votta protect voter privacy?**  
A: Votta uses zero-knowledge proofs to verify vote validity without revealing individual votes. Only aggregated vote counts are stored on-chain.

**Q: Can I run multiple elections simultaneously?**  
A: Yes, the system supports multiple voting polls through the VotingFactory contract.

**Q: Who pays for transaction gas fees?**  
A: The VotingPaymaster contract covers gas costs for voting transactions, making the system free to use for voters.

**Q: How can I verify that my vote was counted?**  
A: Voters receive a cryptographic receipt that they can verify against the Merkle tree root published on-chain.

### Technical Questions

**Q: What blockchain networks are supported?**  
A: The system is designed for Ethereum and Ethereum L2 networks like Optimism and Arbitrum.

**Q: How are credentials issued?**  
A: Credentials are issued through a multi-signature process requiring approval from both a government authority and an independent NGO.

**Q: What happens if fraud is detected?**  
A: The Watch-Tower service can challenge fraudulent batches within the challenge window. If the challenge is valid, the fraudulent batch is reverted and the aggregator is penalized.

**Q: How many votes can be processed per batch?**  
A: Each batch can contain thousands of votes, with the exact limit configurable based on network conditions and gas costs.

**Q: How are zero-knowledge proofs generated?**  
A: The system uses the Plonk proving system, with proofs generated off-chain by the Aggregator service.

## Contributing

We welcome contributions to the Votta e-voting system! Please follow these steps:

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/my-feature`
3. Commit your changes: `git commit -am 'Add new feature'`
4. Push to the branch: `git push origin feature/my-feature`
5. Submit a pull request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
