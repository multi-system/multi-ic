import Principal "mo:base/Principal";
import Debug "mo:base/Debug";
import Array "mo:base/Array";
import { test; suite } "mo:test";

import Types "../../../../multi_backend/types/Types";
import RewardTypes "../../../../multi_backend/types/RewardTypes";
import SystemStakeTypes "../../../../multi_backend/types/SystemStakeTypes";
import PhantomPositionSettlement "../../../../multi_backend/competition/settlement/PhantomPositionSettlement";
import CompetitionTestUtils "../CompetitionTestUtils";
import TokenAccessHelper "../../../../multi_backend/helper/TokenAccessHelper";

suite(
  "Phantom Position Settlement",
  func() {
    // Helper to create a test system stake
    let createTestSystemStake = func() : SystemStakeTypes.SystemStake {
      let govToken = CompetitionTestUtils.getGovToken();
      let multiToken = CompetitionTestUtils.getMultiToken();

      let govSystemStake : Types.Amount = {
        token = govToken;
        value = 50_000;
      };

      let multiSystemStake : Types.Amount = {
        token = multiToken;
        value = 25_000;
      };

      // System stakes array
      let systemStakes : [(Types.Token, Types.Amount)] = [
        (govToken, govSystemStake),
        (multiToken, multiSystemStake),
      ];

      // Create phantom positions for test tokens
      let token1 = CompetitionTestUtils.getTestToken1();
      let token2 = CompetitionTestUtils.getTestToken2();

      let phantomPos1 : Types.Amount = {
        token = token1;
        value = 10_000;
      };

      let phantomPos2 : Types.Amount = {
        token = token2;
        value = 5_000;
      };

      let phantomPositions : [(Types.Token, Types.Amount)] = [
        (token1, phantomPos1),
        (token2, phantomPos2),
      ];

      {
        systemStakes = systemStakes;
        phantomPositions = phantomPositions;
      };
    };

    test(
      "creates position record with correct data",
      func() {
        let phantomSettlement = PhantomPositionSettlement.PhantomPositionSettlement();
        let systemStake = createTestSystemStake();

        // Test token and amount for the phantom position
        let testToken = CompetitionTestUtils.getTestToken1();
        let amount : Types.Amount = {
          token = testToken;
          value = 15_000;
        };

        // Call the function under test
        let position = phantomSettlement.createPhantomPosition(
          testToken,
          amount,
          systemStake,
        );

        // Verify the position properties
        assert (position.isSystem == true);
        assert (position.submissionId == null);
        assert (position.quantity.value == 15_000);
        assert (Principal.equal(position.quantity.token, testToken));

        // Verify system stake references
        assert (position.stakes.size() == 2); // Should have two stake tokens

        // Find the gov stake in the stakes array
        let govStake = TokenAccessHelper.findInTokenArray(position.stakes, CompetitionTestUtils.getGovToken());
        switch (govStake) {
          case (?stake) {
            assert (stake.value == 50_000);
            assert (Principal.equal(stake.token, CompetitionTestUtils.getGovToken()));
          };
          case null {
            assert false; // Should have gov stake
          };
        };

        // Find the multi stake in the stakes array
        let multiStake = TokenAccessHelper.findInTokenArray(position.stakes, CompetitionTestUtils.getMultiToken());
        switch (multiStake) {
          case (?stake) {
            assert (stake.value == 25_000);
            assert (Principal.equal(stake.token, CompetitionTestUtils.getMultiToken()));
          };
          case null {
            assert false; // Should have multi stake
          };
        };
      },
    );

    test(
      "handles multiple phantom positions",
      func() {
        let phantomSettlement = PhantomPositionSettlement.PhantomPositionSettlement();
        let systemStake = createTestSystemStake();

        // Create positions for both phantom tokens
        let positions = Array.map<(Types.Token, Types.Amount), RewardTypes.Position>(
          systemStake.phantomPositions,
          func((token, amount)) {
            phantomSettlement.createPhantomPosition(token, amount, systemStake);
          },
        );

        // Verify we got the right number of positions
        assert (positions.size() == 2);

        // Verify first position
        assert (positions[0].isSystem == true);
        assert (positions[0].submissionId == null);
        assert (positions[0].quantity.value == 10_000);
        assert (Principal.equal(positions[0].quantity.token, CompetitionTestUtils.getTestToken1()));

        // Verify all positions have the same system stakes
        assert (positions[0].stakes.size() == 2);

        // Find gov stake in first position
        let govStake0 = TokenAccessHelper.findInTokenArray(positions[0].stakes, CompetitionTestUtils.getGovToken());
        switch (govStake0) {
          case (?stake) {
            assert (stake.value == 50_000);
          };
          case null {
            assert false;
          };
        };

        // Verify second position
        assert (positions[1].isSystem == true);
        assert (positions[1].submissionId == null);
        assert (positions[1].quantity.value == 5_000);
        assert (Principal.equal(positions[1].quantity.token, CompetitionTestUtils.getTestToken2()));

        // Verify second position has same system stakes
        assert (positions[1].stakes.size() == 2);

        // Find gov stake in second position
        let govStake1 = TokenAccessHelper.findInTokenArray(positions[1].stakes, CompetitionTestUtils.getGovToken());
        switch (govStake1) {
          case (?stake) {
            assert (stake.value == 50_000);
          };
          case null {
            assert false;
          };
        };
      },
    );

    test(
      "handles edge cases",
      func() {
        let phantomSettlement = PhantomPositionSettlement.PhantomPositionSettlement();
        let systemStake = createTestSystemStake();

        // Test with zero value
        let zeroToken = CompetitionTestUtils.getTestToken1();
        let zeroAmount : Types.Amount = {
          token = zeroToken;
          value = 0;
        };

        let zeroPosition = phantomSettlement.createPhantomPosition(
          zeroToken,
          zeroAmount,
          systemStake,
        );

        // Verify zero value position
        assert (zeroPosition.isSystem == true);
        assert (zeroPosition.quantity.value == 0);
        assert (Principal.equal(zeroPosition.quantity.token, zeroToken));

        // Verify it still has the system stakes
        assert (zeroPosition.stakes.size() == 2);

        // Test with very large value
        let largeToken = CompetitionTestUtils.getTestToken2();
        let largeAmount : Types.Amount = {
          token = largeToken;
          value = 999_999_999_999;
        };

        let largePosition = phantomSettlement.createPhantomPosition(
          largeToken,
          largeAmount,
          systemStake,
        );

        // Verify large value position
        assert (largePosition.isSystem == true);
        assert (largePosition.quantity.value == 999_999_999_999);
        assert (Principal.equal(largePosition.quantity.token, largeToken));

        // Verify it still has the system stakes
        assert (largePosition.stakes.size() == 2);
      },
    );
  },
);
