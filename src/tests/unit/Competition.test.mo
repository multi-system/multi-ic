import Debug "mo:base/Debug";
import Principal "mo:base/Principal";
import { test; suite } "mo:test";
import Time "mo:base/Time";
import Competition "../../multi_backend/competition/Competition";

suite(
  "Competition",
  func() {
    let token1 = Principal.fromText("rrkah-fqaaa-aaaaa-aaaaq-cai");
    let token2 = Principal.fromText("renrk-eyaaa-aaaaa-aaada-cai");
    let owner = Principal.fromText("rwlgt-iiaaa-aaaaa-aaaaa-cai");
    let nonOwner = Principal.fromText("r7inp-6aaaa-aaaaa-aaabq-cai");

    let setup = func() : Competition.CompetitionManager {
      Competition.CompetitionManager(owner);
    };

    test(
      "creates competition using system parameters",
      func() {
        let manager = setup();
        let now = Time.now();
        let startTime = now + 3600_000_000_000; // 1 hour in future

        let prices : [Competition.TokenPrice] = [
          {
            token = token1;
            oraclePrice = 100 * Competition.PRICE_SCALE; // $100.00000000
            timestamp = now;
          },
          {
            token = token2;
            oraclePrice = 200 * Competition.PRICE_SCALE; // $200.00000000
            timestamp = now;
          },
        ];

        // Get initial system parameters
        let initialParams = manager.getParameters();

        switch (manager.createCompetition(owner, startTime, prices)) {
          case (#ok(id)) {
            switch (manager.getCompetition(id)) {
              case (?competition) {
                // Verify competition uses current system parameters
                assert competition.maxVolume == initialParams.maxVolume;
                assert competition.minGovStake == initialParams.minGovStake;
                assert competition.markup == initialParams.markup;
                assert competition.startTime == startTime;
              };
              case null { assert false };
            };
          };
          case (#err(msg)) {
            Debug.print("Failed to create competition: " # msg);
            assert false;
          };
        };
      },
    );

    test(
      "competition keeps original parameters after system update",
      func() {
        let manager = setup();
        let now = Time.now();
        let startTime = now + 3600_000_000_000;

        let prices : [Competition.TokenPrice] = [{
          token = token1;
          oraclePrice = 100 * Competition.PRICE_SCALE;
          timestamp = now;
        }];

        // Create first competition
        let competitionId = switch (manager.createCompetition(owner, startTime, prices)) {
          case (#ok(id)) { id };
          case (#err(msg)) {
            Debug.print("Failed to create competition: " # msg);
            assert false;
            0; // unreachable
          };
        };

        // Update system parameters
        let newParams : Competition.SystemParameters = {
          maxVolume = 2_000; // 20% instead of 10%
          minGovStake = 200_000 * Competition.PRICE_SCALE; // doubled
          minMultiStake = 100_000 * Competition.PRICE_SCALE; // doubled
          competitionDuration = 7200; // doubled
          settlementDuration = 3600; // doubled
          distributionPeriod = 172800; // doubled
          numDistributions = 48; // doubled
          markup = 1000; // 10% instead of 5%
        };

        switch (manager.updateParameters(owner, newParams)) {
          case (#ok()) {};
          case (#err(msg)) {
            Debug.print("Failed to update parameters: " # msg);
            assert false;
          };
        };

        // Verify original competition keeps old parameters
        switch (manager.getCompetition(competitionId)) {
          case (?competition) {
            assert competition.maxVolume == 1_000; // Original 10%
            assert competition.markup == 500; // Original 5%
          };
          case null { assert false };
        };

        // Create new competition and verify it uses new parameters
        switch (manager.createCompetition(owner, startTime + 7200_000_000_000, prices)) {
          case (#ok(id)) {
            switch (manager.getCompetition(id)) {
              case (?competition) {
                assert competition.maxVolume == 2_000; // New 20%
                assert competition.markup == 1000; // New 10%
              };
              case null { assert false };
            };
          };
          case (#err(msg)) {
            Debug.print("Failed to create second competition: " # msg);
            assert false;
          };
        };
      },
    );

    test(
      "only owner can update parameters",
      func() {
        let manager = setup();

        let newParams : Competition.SystemParameters = {
          maxVolume = 2_000;
          minGovStake = 200_000 * Competition.PRICE_SCALE;
          minMultiStake = 100_000 * Competition.PRICE_SCALE;
          competitionDuration = 7200;
          settlementDuration = 3600;
          distributionPeriod = 172800;
          numDistributions = 48;
          markup = 1000;
        };

        switch (manager.updateParameters(nonOwner, newParams)) {
          case (#ok()) { assert false };
          case (#err(msg)) {
            assert msg == "Unauthorized";
          };
        };
      },
    );

    test(
      "validates parameter bounds",
      func() {
        let manager = setup();

        let invalidParams : Competition.SystemParameters = {
          maxVolume = 20_000; // 200% - invalid
          minGovStake = 200_000 * Competition.PRICE_SCALE;
          minMultiStake = 100_000 * Competition.PRICE_SCALE;
          competitionDuration = 7200;
          settlementDuration = 3600;
          distributionPeriod = 172800;
          numDistributions = 48;
          markup = 1000;
        };

        switch (manager.updateParameters(owner, invalidParams)) {
          case (#ok()) { assert false };
          case (#err(msg)) {
            assert msg == "Max volume cannot exceed 100%";
          };
        };
      },
    );

    test(
      "competition must start in future",
      func() {
        let manager = setup();
        let now = Time.now();

        let prices : [Competition.TokenPrice] = [{
          token = token1;
          oraclePrice = 100 * Competition.PRICE_SCALE;
          timestamp = now;
        }];

        switch (manager.createCompetition(owner, now, prices)) {
          case (#ok(_)) { assert false };
          case (#err(msg)) {
            assert msg == "Competition must start in the future";
          };
        };
      },
    );
  },
);
