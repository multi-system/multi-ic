#!/usr/bin/env bash
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

# Helper functions
print_green() { echo -e "${GREEN}$1${NC}"; }
print_error() { echo -e "${RED}$1${NC}"; }

# Setup test identity
setup_test_identity() {
  if ! (dfx identity list | grep multi-token-test 2>&1 >/dev/null) ; then
    dfx identity import multi-token-test --storage-mode plaintext <(cat <<EOF
-----BEGIN EC PRIVATE KEY-----
MHQCAQEEICJxApEbuZznKFpV+VKACRK30i6+7u5Z13/DOl18cIC+oAcGBSuBBAAK
oUQDQgAEPas6Iag4TUx+Uop+3NhE6s3FlayFtbwdhRVjvOar0kPTfE/N8N6btRnd
74ly5xXEBNSXiENyxhEuzOZrIWMCNQ==
-----END EC PRIVATE KEY-----
EOF
    )
  fi
}

main() {
  # Setup identity
  print_green "=== Setting up test identity ==="
  setup_test_identity
  export MINTER=$(dfx identity get-principal --identity multi-token-test)
  
  # Create canisters
  print_green "=== Creating canisters ==="
  dfx canister create --all
  
  # Deploy backing tokens
  for token in "token_a" "token_b" "token_c"; do
    print_green "Deploying $token..."
    dfx deploy "$token" --argument "(variant {
        Init = record {
          token_name = \"${token}\";
          token_symbol = \"${token:(-1)}\";
          minting_account = record {
            owner = principal \"${MINTER}\";
          };
          initial_balances = vec {
            record { record { owner = principal \"${MINTER}\"; }; 100_000_000_000_000; };
          };
          metadata = vec {};
          transfer_fee = 10_000;
          archive_options = record {
            trigger_threshold = 2000;
            num_blocks_to_archive = 1000;
            controller_id = principal \"${MINTER}\";
          };
          feature_flags = opt record {
            icrc2 = true;
          };
        }
      })"
    
    export "${token^^}_CANISTER_ID"=$(dfx canister id "$token")
  done
  
  # Deploy multi token
  print_green "=== Deploying multi token canister ==="
  dfx deploy multi_backend
  
  print_green "=== Deployment completed successfully! ==="
}

main