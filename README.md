# Multi

Multi is a decentralized currency backed by a diversified reserve of tokens, designed to set a new standard for value and stability in the Web3 ecosystem. It achieves this through a unique governance model that incentivizes participants to bet on the long-term performance of tokens, rather than relying on community consensus. This fosters a resilient and adaptive currency design that leverages collective wisdom, allowing anyone to directly contribute their insights. Multi is traded with its underlying reserve tokens in an order book market, with a built-in algorithm that enhances liquidity and market stability.

## Testing Setup

### Unit Tests (Motoko)

The project uses Motoko unit tests with the `motoko-matchers` package. Unit tests can be found in `src/tests/unit/`.

To run unit tests:

```bash
dfx deploy multi_test
dfx canister call multi_test run
```

Test output will be visible in the DFX console logs.

### End-to-End Tests (TypeScript)

E2E tests are written in TypeScript using Vitest and test the canister through its public interface.

To run E2E tests:

```bash
npm test
```

## Running the Project Locally

To test the project locally:

```bash
# Start the replica in the background
dfx start --background

# Deploy canisters to the replica and generate the Candid interface
dfx deploy
```

Alternatively, you can use the provided script to automate these steps along with running tests:

```bash
./run_tests.sh
```

Ensure the script has executable permissions:

```bash
chmod +x run_tests.sh
```

## Development Workflow

1. **Making Backend Changes**
   - Edit Motoko files in `src/multi_backend/`.
   - Run `dfx deploy` to deploy changes.
   - Run unit and E2E tests to verify changes.
   - Alternatively, use `./run_tests.sh` for automated deployment and testing.

2. **Adding Tests**
   - **Unit Tests:** Add test cases to `src/tests/unit/test.mo`.
   - **E2E Tests:** Add test cases to `src/tests/e2e/e2e_tests_backend.test.ts`.

## Package Management

This project uses Mops for Motoko package management:

```bash
# Add a package
mops add <package-name>

# Install packages
mops install
```

## Commands Reference

```bash
# Development
dfx start --background   # Start the local replica
dfx deploy               # Deploy all canisters
npm run generate         # Generate Candid interface

# Testing
dfx deploy multi_test    # Deploy and run Motoko unit tests
npm test                 # Run E2E tests
./run_tests.sh           # Run the automated test workflow script

# Package Management
mops add <package>       # Add a new package
mops install             # Install all packages
```