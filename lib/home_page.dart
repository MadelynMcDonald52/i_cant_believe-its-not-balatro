import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart' hide Provider;
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';
import 'package:solitaire/context/card_game_context.dart';
import 'package:solitaire/dialogs/about_dialog.dart';
import 'package:solitaire/dialogs/achievement_dialog.dart';
import 'package:solitaire/dialogs/customization_dialog.dart';
import 'package:solitaire/dialogs/settings_dialog.dart';
import 'package:solitaire/dialogs/support_dialog.dart';
import 'package:solitaire/game_view.dart';
import 'package:solitaire/games/solitaire.dart';
import 'package:solitaire/model/background.dart';
import 'package:solitaire/model/difficulty.dart';
import 'package:solitaire/model/game.dart';
import 'package:solitaire/providers/save_state_notifier.dart';
import 'package:solitaire/utils/build_context_extensions.dart';
import 'package:solitaire/utils/constraints_extensions.dart';
import 'package:solitaire/widgets/keep_alive_container.dart';
import 'package:utils/utils.dart';

typedef GameDetails = ({
  Widget Function(Difficulty, bool startWithTutorial) builder,
  Function(Game, bool startWithTutorial) onStartGame,
});

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  Map<Game, Widget Function(Difficulty, bool startWithTutorial)> get gameBuilders => {
        Game.klondike: (Difficulty difficulty, bool startWithTutorial) => Solitaire(
              difficulty: difficulty,
              startWithTutorial: startWithTutorial,
            ),
     
      };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final saveState = ref.watch(saveStateNotifierProvider).valueOrNull;
    if (saveState == null) {
      return SizedBox.shrink();
    }

    return HookBuilder(
      builder: (context) {
        final gameDetails = gameBuilders.map((game, builder) => MapEntry(game, (
              builder: builder,
              onStartGame: (game, startWithTutorial) {
                context.pushReplacement(
                  () => GameView(cardGame: builder(Difficulty.classic, startWithTutorial)),
                );
                ref.read(saveStateNotifierProvider.notifier).saveGameStarted(
                      game: game,
                      difficulty: Difficulty.classic,
                    );
              },
            )));

        return Scaffold(
          appBar: AppBar(
            forceMaterialTransparency: true,
            actions: [
              Tooltip(
                message: 'Achievements',
                child: IconButton(
                  icon: Icon(Symbols.military_tech, fill: 1),
                  onPressed: () => AchievementDialog.show(context),
                ),
              ),
              
            ],
          ),
          body: Provider.value(
            value: CardGameContext(isPreview: true),
            child: LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.largestAxis == Axis.horizontal) {
                  return buildHorizontalLayout(
                    context,
                    lastGamePlayed: saveState.lastGamePlayed,
                    gameDetails: gameDetails,
                    background: saveState.background,
                  );
                } else {
                  return buildVerticalLayout(
                    context,
                    lastGamePlayed: saveState.lastGamePlayed,
                    gameDetails: gameDetails,
                    background: saveState.background,
                  );
                }
              },
            ),
          ),
        );
      },
    );
  }

  Widget gameTitle(
    BuildContext context,
    Game game, {
    TextAlign textAlign = TextAlign.center,
  }) {
    if (game == Game.klondike) {
      return Image.asset(
        'assets/images/app_icon.png',
        height: 72,
        fit: BoxFit.contain,
      );
    }

    return Text(
      game.title,
      textAlign: textAlign,
      style: Theme.of(context).textTheme.headlineLarge,
    );
  }

  Widget buildHorizontalLayout(
    BuildContext context, {
    required Game? lastGamePlayed,
    required Map<Game, GameDetails> gameDetails,
    required Background background,
  }) {
    return HookBuilder(
      key: ValueKey('horizontal'),
      builder: (context) {
        final selectedGameState = useState(lastGamePlayed ?? Game.klondike);
        final (:builder, :onStartGame) = gameDetails[selectedGameState.value]!;

        return Row(
          children: [
            Expanded(
              child: MediaQuery.removePadding(
                context: context,
                removeLeft: true,
                removeTop: true,
                removeRight: true,
                removeBottom: true,
                child: ListView.separated(
                  padding: EdgeInsets.symmetric(horizontal: 16) +
                      EdgeInsets.only(
                        bottom: max(MediaQuery.paddingOf(context).bottom + 16, 32),
                      ),
                  itemCount: gameDetails.length,
                  itemBuilder: (_, i) {
                    final (game, details) = gameDetails.entryRecords.toList()[i];
                    final builder = details.builder;
                    return KeepAliveContainer(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Material(
                          color: Colors.transparent,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: selectedGameState.value == game ? BorderSide(width: 4) : BorderSide.none,
                          ),
                          child: AspectRatio(
                            aspectRatio: 3 / 2,
                            child: Stack(
                              children: [
                                Positioned.fill(child: background.build()),
                                IgnorePointer(child: builder(Difficulty.classic, false)),
                                Positioned.fill(
                                  child: ColoredBox(
                                      color: Colors.white.withValues(alpha: 0.7),
                                    child: InkWell(
                                      onTap: () => selectedGameState.value = game,
                                      child: Center(
                                        child: gameTitle(
                                          context,
                                          game,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                  separatorBuilder: (_, __) => SizedBox(height: 16),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 48),
                child: Column(
                  spacing: 8,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    gameTitle(
                      context,
                      selectedGameState.value,
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      spacing: 8,
                      children: [
                        SizedBox(width: 48),
                        ElevatedButton(
                          onPressed: () => onStartGame(selectedGameState.value, false),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.black,
                            foregroundColor: Colors.white,
                          ),
                          child: Text('Play'),
                        ),
                        Tooltip(
                          message: 'Learn to Play',
                          child: IconButton(
                            constraints: BoxConstraints.tightFor(width: 32, height: 32),
                            icon: Icon(Symbols.question_mark, fill: 1, size: 14),
                            onPressed: () => onStartGame(selectedGameState.value, true),
                            style: IconButton.styleFrom(
                              backgroundColor: Color(0xFFAAAAAA),
                              foregroundColor: Colors.black,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget buildVerticalLayout(
    BuildContext context, {
    required Game? lastGamePlayed,
    required Map<Game, GameDetails> gameDetails,
    required Background background,
  }) {
    return HookBuilder(
      key: ValueKey('vertical'),
      builder: (context) {
        final pageState = useState(lastGamePlayed == null ? 0 : gameDetails.keys.toList().indexOf(lastGamePlayed));
        final pageController = usePageController(initialPage: pageState.value);

        return Column(
          children: [
            Expanded(
              child: MediaQuery.removePadding(
                removeTop: true,
                removeBottom: true,
                context: context,
                child: PageView(
                  controller: pageController,
                  onPageChanged: (page) => pageState.value = page,
                  children: gameDetails.mapToIterable((game, details) {
                    final (:builder, :onStartGame) = details;

                    return KeepAliveContainer(
                      child: Padding(
                        padding: EdgeInsets.symmetric(horizontal: 16),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(16),
                          child: Stack(
                            children: [
                              Positioned.fill(child: background.build()),
                              IgnorePointer(child: builder(Difficulty.classic, false)),
                              Positioned.fill(
                                child: ColoredBox(color: Colors.white.withValues(alpha: 0.8)),
                              ),
                              Positioned.fill(
                                child: Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 16),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    children: [
                                      gameTitle(
                                        context,
                                        game,
                                      ),
                                      Row(
                                        spacing: 8,
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          SizedBox(width: 48),
                                          ElevatedButton(
                                            onPressed: () => onStartGame(game, false),
                                            style: ElevatedButton.styleFrom(
                                              backgroundColor: Colors.black,
                                              foregroundColor: Colors.white,
                                            ),
                                            child: Text('Play'),
                                          ),
                                          Tooltip(
                                            message: 'Learn to Play',
                                            child: IconButton(
                                              constraints: BoxConstraints.tightFor(width: 32, height: 32),
                                              icon: Icon(Symbols.question_mark, fill: 1, size: 14),
                                              onPressed: () => onStartGame(game, true),
                                              style: IconButton.styleFrom(
                                                backgroundColor: Color(0xFFAAAAAA),
                                                foregroundColor: Colors.black,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
            SizedBox(height: 16),
            AnimatedSmoothIndicator(
              activeIndex: pageState.value,
              count: gameBuilders.length,
              effect: WormEffect(
                activeDotColor: Colors.black,
              ),
            ),
            SizedBox(height: max(MediaQuery.paddingOf(context).bottom + 32, 48)),
          ],
        );
      },
    );
  }
}
