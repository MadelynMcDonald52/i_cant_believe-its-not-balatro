import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:solitaire/games/solitaire.dart';
import 'package:solitaire/main.dart';
import 'package:solitaire/model/achievement.dart';
import 'package:solitaire/model/difficulty.dart';
import 'package:solitaire/model/game.dart';
import 'package:solitaire/providers/save_state_notifier.dart';

part 'achievement_service.g.dart';

class AchievementService {
  final Ref ref;

  const AchievementService(this.ref);

  Future<void> checkGameCompletionAchievements({
    required Game game,
    required Difficulty difficulty,
    required Duration duration,
  }) async {}

  Future<void> markJokerCollected(JokerType joker) => _markAchievement(_achievementForJoker(joker));

  Future<void> deleteAchievement(Achievement achievement) async {
    final saveState = await ref.read(saveStateNotifierProvider.future);
    if (!saveState.achievements.contains(achievement)) {
      return;
    }

    await ref.read(saveStateNotifierProvider.notifier).deleteAchievement(achievement: achievement);

    final context = scaffoldMessengerKey.currentContext;
    if (context != null) {
      scaffoldMessengerKey.currentState?.showSnackBar(
        SnackBar(content: Text('Achievement "${achievement.name}" Deleted!')),
      );
    }
  }

  Future<void> _markAchievement(Achievement achievement) async {
    final saveState = await ref.read(saveStateNotifierProvider.future);
    if (saveState.achievements.contains(achievement)) {
      return;
    }

    await ref.read(saveStateNotifierProvider.notifier).saveAchievement(achievement: achievement);

    final context = scaffoldMessengerKey.currentContext;
    if (context != null) {
      scaffoldMessengerKey.currentState?.showSnackBar(SnackBar(
        content: Row(
          spacing: 16,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox.square(
                dimension: 48,
                child: Image.asset(
                  achievement.assetPath,
                  fit: BoxFit.cover,
                ),
              ),
            ),
            Text('Achievement "${achievement.name}" Unlocked!'),
          ],
        ),
      ));
    }
  }

  Achievement _achievementForJoker(JokerType joker) => switch (joker) {
        JokerType.joker1 => Achievement.joker1,
        JokerType.joker2 => Achievement.joker2,
        JokerType.joker3 => Achievement.joker3,
        JokerType.joker4 => Achievement.joker4,
        JokerType.joker5 => Achievement.joker5,
        JokerType.joker6 => Achievement.joker6,
      };
}

@Riverpod(keepAlive: true)
AchievementService achievementService(Ref ref) => AchievementService(ref);
