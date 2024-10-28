// src/tests/unit/token_utils.test.mo
import Debug "mo:base/Debug";
import Principal "mo:base/Principal";
import Time "mo:base/Time";
import Nat64 "mo:base/Nat64";
import { test; suite } "mo:test";
import TokenUtils "../../../src/multi_backend/token_utils";

suite(
  "Token Utils - Core ICRC2 Validations",
  func() {
    let owner = Principal.fromText("2vxsx-fae");
    let spender = Principal.fromText("rrkah-fqaaa-aaaaa-aaaaq-cai");
    let current_time : Nat64 = 1_000_000;

    test(
      "validateApproval rejects zero amount",
      func() {
        let args : TokenUtils.ApproveArgs = {
          from_subaccount = null;
          spender = { owner = spender; subaccount = null };
          amount = 0;
          expires_at = null;
          fee = ?TokenUtils.DEFAULT_FEE;
          memo = null;
          created_at_time = null;
          expected_allowance = null;
        };

        switch (TokenUtils.validateApproval(args, current_time, null)) {
          case (#err(msg)) {
            assert msg == "Amount must be greater than 0";
          };
          case (#ok()) { assert false };
        };
      },
    );

    test(
      "validateApproval validates expiry time",
      func() {
        let args : TokenUtils.ApproveArgs = {
          from_subaccount = null;
          spender = { owner = spender; subaccount = null };
          amount = 1_000;
          expires_at = ?(current_time - 1);
          fee = ?TokenUtils.DEFAULT_FEE;
          memo = null;
          created_at_time = null;
          expected_allowance = null;
        };

        switch (TokenUtils.validateApproval(args, current_time, null)) {
          case (#err(msg)) {
            assert msg == "Expiry time must be in the future";
          };
          case (#ok()) { assert false };
        };
      },
    );

    test(
      "validateApproval checks expected allowance",
      func() {
        let args : TokenUtils.ApproveArgs = {
          from_subaccount = null;
          spender = { owner = spender; subaccount = null };
          amount = 1_000;
          expires_at = null;
          fee = ?TokenUtils.DEFAULT_FEE;
          memo = null;
          created_at_time = null;
          expected_allowance = ?500;
        };

        let existing : TokenUtils.Allowance = {
          allowance = 500;
          expires_at = null;
        };

        switch (TokenUtils.validateApproval(args, current_time, ?existing)) {
          case (#err(msg)) { assert false };
          case (#ok()) { assert true };
        };
      },
    );
  },
);
