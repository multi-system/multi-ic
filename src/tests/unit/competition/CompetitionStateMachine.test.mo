import { suite; test; expect } "mo:test";
import Time "mo:base/Time";
import Nat "mo:base/Nat";

import CompetitionStateMachine "../../../multi_backend/competition/CompetitionStateMachine";
import CompetitionEntryTypes "../../../multi_backend/types/CompetitionEntryTypes";
import CompetitionTestUtils "./CompetitionTestUtils";

suite(
  "Competition State Machine",
  func() {
    // Helper to create a test competition with specific parameters
    func createTestCompetition(
      status : CompetitionEntryTypes.CompetitionStatus,
      startTime : Time.Time,
      lastDistributionIndex : ?Nat,
    ) : CompetitionEntryTypes.Competition {
      let competition = CompetitionTestUtils.createCompetitionEntry();
      {
        competition with
        status = status;
        startTime = startTime;
        lastDistributionIndex = lastDistributionIndex;
      };
    };

    test(
      "transitions from PreAnnouncement to AcceptingStakes",
      func() {
        let startTime : Time.Time = 1_000_000_000_000_000; // 1 million seconds
        let competition = createTestCompetition(#PreAnnouncement, startTime, null);

        // Before pre-announcement period ends
        let earlyTime = startTime + competition.config.preAnnouncementDuration - 1;
        let action1 = CompetitionStateMachine.checkHeartbeatAction(competition, earlyTime);
        expect.bool(action1 == #None).isTrue();

        // Exactly when pre-announcement period ends
        let transitionTime = startTime + competition.config.preAnnouncementDuration;
        let action2 = CompetitionStateMachine.checkHeartbeatAction(competition, transitionTime);
        expect.bool(action2 == #StartStaking).isTrue();

        // After pre-announcement period
        let lateTime = startTime + competition.config.preAnnouncementDuration + 1;
        let action3 = CompetitionStateMachine.checkHeartbeatAction(competition, lateTime);
        expect.bool(action3 == #StartStaking).isTrue();
      },
    );

    test(
      "transitions from AcceptingStakes to Distribution",
      func() {
        let startTime : Time.Time = 1_000_000_000_000_000;
        let competition = createTestCompetition(#AcceptingStakes, startTime, null);

        // Before competition cycle ends
        let earlyTime = startTime + competition.config.competitionCycleDuration - 1;
        let action1 = CompetitionStateMachine.checkHeartbeatAction(competition, earlyTime);
        expect.bool(action1 == #None).isTrue();

        // Exactly when competition cycle ends
        let transitionTime = startTime + competition.config.competitionCycleDuration;
        let action2 = CompetitionStateMachine.checkHeartbeatAction(competition, transitionTime);
        expect.bool(action2 == #EndStaking).isTrue();

        // After competition cycle ends
        let lateTime = startTime + competition.config.competitionCycleDuration + 1;
        let action3 = CompetitionStateMachine.checkHeartbeatAction(competition, lateTime);
        expect.bool(action3 == #EndStaking).isTrue();
      },
    );

    test(
      "processes distribution events correctly",
      func() {
        let startTime : Time.Time = 1_000_000_000_000_000;
        let stakingEndTime = startTime + 1_000_000_000_000_000; // competition cycle duration
        let competition = createTestCompetition(#Distribution, startTime, null);

        // First distribution event
        let firstDistTime = stakingEndTime + 1; // Just after staking ends
        let action1 = CompetitionStateMachine.checkHeartbeatAction(competition, firstDistTime);
        expect.bool(action1 == #DistributeReward).isTrue();

        // After first distribution is processed
        let competitionAfterFirst = {
          competition with
          lastDistributionIndex = ?0;
        };

        // Before second distribution time
        let beforeSecond = stakingEndTime + competition.config.rewardDistributionDuration - 1;
        let action2 = CompetitionStateMachine.checkHeartbeatAction(competitionAfterFirst, beforeSecond);
        expect.bool(action2 == #None).isTrue();

        // Second distribution event
        let secondDistTime = stakingEndTime + competition.config.rewardDistributionDuration;
        let action3 = CompetitionStateMachine.checkHeartbeatAction(competitionAfterFirst, secondDistTime);
        expect.bool(action3 == #DistributeReward).isTrue();
      },
    );

    test(
      "ends competition after all distributions",
      func() {
        let startTime : Time.Time = 1_000_000_000_000_000;
        let stakingEndTime = startTime + 1_000_000_000_000_000;
        let numEvents = 10; // from config

        // Competition with all distributions complete
        let competition = createTestCompetition(#Distribution, startTime, ?(numEvents - 1));

        // After all distributions
        let endTime = stakingEndTime + (competition.config.rewardDistributionDuration * numEvents);
        let action = CompetitionStateMachine.checkHeartbeatAction(competition, endTime);
        expect.bool(action == #EndCompetition).isTrue();
      },
    );

    test(
      "identifies active competitions correctly",
      func() {
        let competition1 = createTestCompetition(#PreAnnouncement, 0, null);
        expect.bool(CompetitionStateMachine.isCompetitionActive(competition1)).isTrue();

        let competition2 = createTestCompetition(#AcceptingStakes, 0, null);
        expect.bool(CompetitionStateMachine.isCompetitionActive(competition2)).isTrue();

        let competition3 = createTestCompetition(#Finalizing, 0, null);
        expect.bool(CompetitionStateMachine.isCompetitionActive(competition3)).isFalse();

        let competition4 = createTestCompetition(#Distribution, 0, null);
        expect.bool(CompetitionStateMachine.isCompetitionActive(competition4)).isFalse();

        let competition5 = createTestCompetition(#Completed, 0, null);
        expect.bool(CompetitionStateMachine.isCompetitionActive(competition5)).isFalse();
      },
    );

    test(
      "determines when to create new competition",
      func() {
        // No competitions
        let shouldCreate1 = CompetitionStateMachine.shouldCreateNewCompetition([], 0);
        expect.bool(shouldCreate1).isTrue();

        // One active competition
        let activeComp = createTestCompetition(#AcceptingStakes, 0, null);
        let shouldCreate2 = CompetitionStateMachine.shouldCreateNewCompetition([activeComp], 0);
        expect.bool(shouldCreate2).isFalse();

        // Only completed competitions
        let completedComp = createTestCompetition(#Completed, 0, null);
        let distributingComp = createTestCompetition(#Distribution, 0, null);
        let shouldCreate3 = CompetitionStateMachine.shouldCreateNewCompetition([completedComp, distributingComp], 0);
        expect.bool(shouldCreate3).isTrue();
      },
    );

    test(
      "identifies when price events are needed",
      func() {
        expect.bool(CompetitionStateMachine.needsPriceEvent(#None)).isFalse();
        expect.bool(CompetitionStateMachine.needsPriceEvent(#StartStaking)).isTrue();
        expect.bool(CompetitionStateMachine.needsPriceEvent(#EndStaking)).isFalse();
        expect.bool(CompetitionStateMachine.needsPriceEvent(#DistributeReward)).isTrue();
        expect.bool(CompetitionStateMachine.needsPriceEvent(#EndCompetition)).isFalse();
      },
    );

    test(
      "calculates next competition start time correctly",
      func() {
        let startTime : Time.Time = 1_000_000_000_000_000;
        let competition = createTestCompetition(#AcceptingStakes, startTime, null);

        let nextStartTime = CompetitionStateMachine.calculateNextCompetitionStartTime(competition);
        expect.int(nextStartTime).equal(startTime + competition.config.competitionCycleDuration);
      },
    );
  },
);
