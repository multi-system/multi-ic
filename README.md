# Multi

Multi is a decentralized currency backed by a diversified reserve of tokens, designed to set a new standard for value and stability in the Web3 ecosystem. It achieves this through a unique governance model that incentivizes participants to bet on the long-term performance of tokens, rather than relying on community consensus. This fosters a resilient and adaptive currency design that leverages collective wisdom, allowing anyone to directly contribute their insights. Multi is traded with its underlying reserve tokens in an order book market, with a built-in algorithm that enhances liquidity and market stability.

## Setup and Installation

```bash
# Install dependencies
yarn install
mops install
```

## Testing Setup

### Unit Tests (Motoko)

The project uses Motoko unit tests with the `mo:test` package. Unit tests can be found in `src/tests/unit/`.
To run unit tests:

```bash
mops test
```

Test output will be visible in the console logs.

### End-to-End Tests (TypeScript)

E2E tests are written in TypeScript using Vitest and test the canister through its public interface.
To run E2E tests:

```bash
yarn test
```

## Running the Project Locally

To test the project locally:

```bash
# Start the replica in the background
dfx start --background
# Deploy backend canisters
./scripts/deploy-backend.sh
```

For a complete local development experience with frontend:

```bash
# Start local development environment (deploys backend and starts frontend)
yarn local

# In a new terminal, run the demo to see the system in action
yarn demo
```

Alternatively, you can use the provided script to automate testing:

```bash
yarn test:full
```

## Commands Reference

```bash
# Development
dfx start --background  # Start the local replica
./scripts/deploy-backend.sh  # Deploy backend canisters
yarn generate           # Generate Candid interface
yarn local              # Start complete dev environment with frontend
yarn demo               # Run demo operations (requires yarn local)

# Testing
mops test               # Run Motoko unit tests
yarn test               # Run E2E tests
yarn test:full          # Run the automated test workflow script

# Package Management
mops add                # Add a new package
mops install            # Install all packages
```
