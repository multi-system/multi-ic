#!/usr/bin/env bash
set -euo pipefail
# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'
# Helper functions
print_green() { echo -e "${GREEN}$1${NC}"; }
print_error() { echo -e "${RED}$1${NC}"; }
print_info() { echo -e "${YELLOW}$1${NC}"; }
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
  dfx identity use multi-token-test
  export MINTER=$(dfx identity get-principal)
 
  # The JS test identity needs initial balance
  export TEST_IDENTITY="jg6qm-uw64t-m6ppo-oluwn-ogr5j-dc5pm-lgy2p-eh6px-hebcd-5v73i-nqe"
 
  # Create canisters
  print_green "=== Creating canisters ==="
  dfx canister create --all

  # Deploy multi backend
  print_green "=== Deploying multi backend canister ==="
  dfx deploy multi_backend
  print_info "Generating declarations for multi_backend..."
  dfx generate multi_backend
 
  # Export multi backend ID
  export MULTI_BACKEND_ID=$(dfx canister id multi_backend)
  print_info "Exported MULTI_BACKEND_ID=${MULTI_BACKEND_ID}"

  # Deploy multi history
  print_green "=== Deploying multi history canister ==="
  dfx deploy multi_history
  print_info "Generating declarations for multi_history..."
  dfx generate multi_history
  
  # Export multi history ID
  export MULTI_HISTORY_ID=$(dfx canister id multi_history)
  print_info "Exported MULTI_HISTORY_ID=${MULTI_HISTORY_ID}"

  # Deploy multi token
  print_green "=== Deploying multi token canister ==="
  dfx deploy multi_token --argument "(variant {
      Init = record {
        token_name = \"Multi Token\";
        token_symbol = \"MULTI\";
        minting_account = record {
          owner = principal \"${MULTI_BACKEND_ID}\";
        };
        initial_balances = vec {};
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
  
  print_info "Generating declarations for multi_token..."
  dfx generate multi_token
  
  # Export multi token ID
  export MULTI_TOKEN_ID=$(dfx canister id multi_token)
  print_info "Exported MULTI_TOKEN_ID=${MULTI_TOKEN_ID}"

  # Deploy governance token
  print_green "=== Deploying governance token canister ==="
  dfx deploy governance_token --argument "(variant {
      Init = record {
        token_name = \"Foresight Token\";
        token_symbol = \"FORESIGHT\";
        minting_account = record {
          owner = principal \"${MINTER}\";
        };
        initial_balances = vec {
          record { record { owner = principal \"${MINTER}\"; }; 100_000_000_000_000; };
          record { record { owner = principal \"${TEST_IDENTITY}\"; }; 100_000_000_000_000; };
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
  print_info "Generating declarations for governance_token..."
  dfx generate governance_token

  # Export governance token ID
  export GOVERNANCE_TOKEN_ID=$(dfx canister id governance_token)
  print_info "Exported GOVERNANCE_TOKEN_ID=${GOVERNANCE_TOKEN_ID}"
 
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
            record { record { owner = principal \"${TEST_IDENTITY}\"; }; 100_000_000_000_000; };
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
   
    # Generate declarations
    print_info "Generating declarations for $token..."
    dfx generate "$token"
   
    # Export canister ID
    canister_id=$(dfx canister id "$token")
    export "${token^^}_CANISTER_ID=$canister_id"
    print_info "Exported ${token^^}_CANISTER_ID=$canister_id"
  done
 
  print_green "=== Deployment completed successfully! ==="
  print_info ""
  print_info "Canister IDs:"
  print_info "  Multi Backend:  ${MULTI_BACKEND_ID}"
  print_info "  Multi History:  ${MULTI_HISTORY_ID}"
  print_info "  Multi Token:    ${MULTI_TOKEN_ID}"
  print_info "  Governance:     ${GOVERNANCE_TOKEN_ID}"
  print_info "  Token A:        $(dfx canister id token_a)"
  print_info "  Token B:        $(dfx canister id token_b)"
  print_info "  Token C:        $(dfx canister id token_c)"
}
# Trap errors
trap 'print_error "An error occurred during deployment"; exit 1' ERR
main