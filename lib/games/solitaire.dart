import 'dart:math';

import 'package:card_game/card_game.dart';
import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:solitaire/model/difficulty.dart';
import 'package:solitaire/model/game.dart';
import 'package:solitaire/services/achievement_service.dart';
import 'package:solitaire/services/audio_service.dart';
import 'package:solitaire/styles/playing_card_builder.dart';
import 'package:solitaire/widgets/card_scaffold.dart';
import 'package:solitaire/widgets/game_tutorial.dart';
import 'package:utils/utils.dart';

enum HandSort { rank, suit }

enum HandKind {
  highCard,
  pair,
  twoPair,
  threeOfAKind,
  straight,
  flush,
  fullHouse,
  fourOfAKind,
  straightFlush,
}

enum JokerType {
  joker1(
    assetName: 'joker1.png',
    title: 'Joker',
    description: 'Doubles any hand score.',
  ),
  joker2(
    assetName: 'joker2.png',
    title: 'Jolly Joker',
    description: 'Quadruples Pair hands.',
  ),
  joker3(
    assetName: 'joker3.png',
    title: 'Zany Joker',
    description: 'Quadruples Three of a Kind hands.',
  ),
  joker4(
    assetName: 'joker4.png',
    title: 'Mad Joker',
    description: 'Quadruples Four of a Kind hands.',
  ),
  joker5(
    assetName: 'joker5.png',
    title: 'Crazy Joker',
    description: 'Quadruples Straight hands.',
  ),
  joker6(
    assetName: 'joker6.png',
    title: 'Droll Joker',
    description: 'Quadruples Flush hands.',
  );

  final String assetName;
  final String title;
  final String description;

  const JokerType({
    required this.assetName,
    required this.title,
    required this.description,
  });

  String get assetPath => 'assets/images/$assetName';

  int scoreFactorFor(HandKind kind) {
    return switch (this) {
      JokerType.joker1 => 2,
      JokerType.joker2 => kind == HandKind.pair ? 4 : 1,
      JokerType.joker3 => kind == HandKind.threeOfAKind ? 4 : 1,
      JokerType.joker4 => kind == HandKind.fourOfAKind ? 4 : 1,
      JokerType.joker5 => kind == HandKind.straight ? 4 : 1,
      JokerType.joker6 => kind == HandKind.flush ? 4 : 1,
    };
  }
}

class BalatroHandScore {
  final String name;
  final int chips;
  final int multiplier;
  final HandKind kind;

  const BalatroHandScore({
    required this.name,
    required this.chips,
    required this.multiplier,
    required this.kind,
  });

  int get total => chips * multiplier;

  BalatroHandScore withMultiplierFactor(int factor) {
    return BalatroHandScore(
      name: name,
      chips: chips,
      multiplier: multiplier * factor,
      kind: kind,
    );
  }

  static BalatroHandScore evaluate(List<SuitedCard> cards) {
    if (cards.isEmpty) {
      return const BalatroHandScore(
        name: 'No Hand',
        chips: 0,
        multiplier: 0,
        kind: HandKind.highCard,
      );
    }

    final ranks = cards.map(SolitaireState.rankValue).toList();
    final counts = <int, int>{};
    for (final rank in ranks) {
      counts.update(rank, (value) => value + 1, ifAbsent: () => 1);
    }

    final groups = counts.values.sorted((a, b) => b.compareTo(a));
    final isFlush = cards.map((card) => card.suit).toSet().length == 1;
    final isStraight = SolitaireState.isStraight(ranks);
    final chipBonus = ranks.fold<int>(0, (sum, rank) => sum + min(rank, 10));

    if (cards.length >= 5 && isStraight && isFlush) {
      return BalatroHandScore(
        name: 'Straight Flush',
        chips: 80 + chipBonus,
        multiplier: 8,
        kind: HandKind.straightFlush,
      );
    }
    if (groups.firstOrNull == 4) {
      return BalatroHandScore(
        name: 'Four of a Kind',
        chips: 70 + chipBonus,
        multiplier: 7,
        kind: HandKind.fourOfAKind,
      );
    }
    if (groups.length > 1 && groups[0] == 3 && groups[1] == 2) {
      return BalatroHandScore(
        name: 'Full House',
        chips: 60 + chipBonus,
        multiplier: 6,
        kind: HandKind.fullHouse,
      );
    }
    if (cards.length >= 5 && isFlush) {
      return BalatroHandScore(
        name: 'Flush',
        chips: 50 + chipBonus,
        multiplier: 5,
        kind: HandKind.flush,
      );
    }
    if (cards.length >= 5 && isStraight) {
      return BalatroHandScore(
        name: 'Straight',
        chips: 45 + chipBonus,
        multiplier: 4,
        kind: HandKind.straight,
      );
    }
    if (groups.firstOrNull == 3) {
      return BalatroHandScore(
        name: 'Three of a Kind',
        chips: 35 + chipBonus,
        multiplier: 3,
        kind: HandKind.threeOfAKind,
      );
    }
    if (groups.where((count) => count == 2).length >= 2) {
      return BalatroHandScore(
        name: 'Two Pair',
        chips: 30 + chipBonus,
        multiplier: 2,
        kind: HandKind.twoPair,
      );
    }
    if (groups.firstOrNull == 2) {
      return BalatroHandScore(
        name: 'Pair',
        chips: 20 + chipBonus,
        multiplier: 2,
        kind: HandKind.pair,
      );
    }

    return BalatroHandScore(
      name: 'High Card',
      chips: 12 + chipBonus,
      multiplier: 1,
      kind: HandKind.highCard,
    );
  }
}

class SolitaireState {
  static const int maxHandSize = 8;
  static const int maxHands = 3;
  static const int maxDiscards = 3;
  static const Object _copySentinel = Object();

  final List<SuitedCard> hand;
  final List<SuitedCard> deck;
  final Set<SuitedCard> selectedCards;
  final int handsPlayed;
  final int discardsUsed;
  final int roundScore;
  final int targetScore;
  final int ante;
  final int round;
  final HandSort sortMode;
  final List<JokerType> jokers;
  final JokerType? pendingJoker;
  final BalatroHandScore? lastScore;
  final List<SolitaireState> history;

  const SolitaireState({
    required this.hand,
    required this.deck,
    required this.selectedCards,
    required this.handsPlayed,
    required this.discardsUsed,
    required this.roundScore,
    required this.targetScore,
    required this.ante,
    required this.round,
    required this.sortMode,
    required this.jokers,
    required this.pendingJoker,
    required this.lastScore,
    required this.history,
  });

  static SolitaireState getInitialState({required Difficulty difficulty}) {
    final deck = SuitedCard.deck.shuffled();
    final openingHand = _sorted(
      deck.take(maxHandSize).toList(),
      HandSort.rank,
    );

    return SolitaireState(
      hand: openingHand,
      deck: deck.skip(maxHandSize).toList(),
      selectedCards: const <SuitedCard>{},
      handsPlayed: 0,
      discardsUsed: 0,
      roundScore: 0,
      targetScore: switch (difficulty) {
        Difficulty.classic => 300,
        Difficulty.royal => 425,
        Difficulty.ace => 600,
      },
      ante: 1,
      round: 1,
      sortMode: HandSort.rank,
      jokers: const [],
      pendingJoker: null,
      lastScore: null,
      history: const [],
    );
  }

  int get handsRemaining => maxHands - handsPlayed;
  int get discardsRemaining => maxDiscards - discardsUsed;
  bool get isVictory => roundScore >= targetScore;
  bool get isGameOver => !isVictory && handsRemaining <= 0;
  bool get hasPendingJoker => pendingJoker != null;

  bool get canPlaySelected =>
      selectedCards.isNotEmpty &&
      selectedCards.length <= 5 &&
      handsRemaining > 0 &&
      !isGameOver &&
      !hasPendingJoker;
  bool get canDiscardSelected =>
      selectedCards.isNotEmpty &&
      selectedCards.length <= 5 &&
      discardsRemaining > 0 &&
      !isGameOver &&
      !hasPendingJoker;

  List<SuitedCard> get orderedSelectedCards => hand.where(selectedCards.contains).toList();

  SolitaireState toggleSelection(SuitedCard card) {
    if (isVictory || isGameOver || hasPendingJoker) {
      return this;
    }

    final nextSelection = {...selectedCards};
    if (nextSelection.contains(card)) {
      nextSelection.remove(card);
    } else {
      if (nextSelection.length >= 5) {
        return this;
      }
      nextSelection.add(card);
    }

    return copyWith(selectedCards: nextSelection, saveToHistory: false);
  }

  SolitaireState sortHand(HandSort mode) {
    if (hasPendingJoker) {
      return this;
    }
    return copyWith(
      hand: _sorted(hand, mode),
      sortMode: mode,
      saveToHistory: false,
    );
  }

  SolitaireState playSelected() {
    if (!canPlaySelected) {
      return this;
    }

    final handScore = _scoreHand(orderedSelectedCards);
    final nextRoundScore = roundScore + handScore.total;

    if (nextRoundScore >= targetScore) {
      return _startNextRound(
        lastScore: handScore,
      );
    }

    return _replaceSelectedCards(
      handsPlayed: handsPlayed + 1,
      discardsUsed: discardsUsed,
      roundScore: nextRoundScore,
      lastScore: handScore,
    );
  }

  SolitaireState collectPendingJoker() {
    final joker = pendingJoker;
    if (joker == null) {
      return this;
    }

    return copyWith(
      jokers: [...jokers, joker],
      pendingJoker: null,
      saveToHistory: false,
    );
  }

  SolitaireState discardSelected() {
    if (!canDiscardSelected) {
      return this;
    }

    return _replaceSelectedCards(
      handsPlayed: handsPlayed,
      discardsUsed: discardsUsed + 1,
      roundScore: roundScore,
      lastScore: lastScore,
    );
  }

  SolitaireState _replaceSelectedCards({
    required int handsPlayed,
    required int discardsUsed,
    required int roundScore,
    required BalatroHandScore? lastScore,
  }) {
    final nextDeck = [...deck];
    final nextHand = hand.where((card) => !selectedCards.contains(card)).toList();

    while (nextHand.length < maxHandSize && nextDeck.isNotEmpty) {
      nextHand.add(nextDeck.removeAt(0));
    }

    return copyWith(
      hand: _sorted(nextHand, sortMode),
      deck: nextDeck,
      selectedCards: <SuitedCard>{},
      handsPlayed: handsPlayed,
      discardsUsed: discardsUsed,
      roundScore: roundScore,
      lastScore: lastScore,
    );
  }

  SolitaireState _startNextRound({
    required BalatroHandScore lastScore,
  }) {
    final nextDeck = SuitedCard.deck.shuffled();
    final openingHand = _sorted(
      nextDeck.take(maxHandSize).toList(),
      sortMode,
    );
    final nextRound = round + 1;
    final awardedJoker = round % 3 == 0 ? _randomJoker() : null;

    return copyWith(
      hand: openingHand,
      deck: nextDeck.skip(maxHandSize).toList(),
      selectedCards: <SuitedCard>{},
      handsPlayed: 0,
      discardsUsed: 0,
      roundScore: 0,
      targetScore: targetScore + 150,
      round: nextRound,
      jokers: jokers,
      pendingJoker: awardedJoker,
      lastScore: lastScore,
    );
  }

  SolitaireState withUndo() {
    return history.last.copyWith(saveToHistory: false);
  }

  SolitaireState copyWith({
    List<SuitedCard>? hand,
    List<SuitedCard>? deck,
    Set<SuitedCard>? selectedCards,
    int? handsPlayed,
    int? discardsUsed,
    int? roundScore,
    int? targetScore,
    int? ante,
    int? round,
    HandSort? sortMode,
    List<JokerType>? jokers,
    Object? pendingJoker = _copySentinel,
    BalatroHandScore? lastScore,
    bool saveToHistory = true,
  }) {
    return SolitaireState(
      hand: hand ?? this.hand,
      deck: deck ?? this.deck,
      selectedCards: selectedCards ?? this.selectedCards,
      handsPlayed: handsPlayed ?? this.handsPlayed,
      discardsUsed: discardsUsed ?? this.discardsUsed,
      roundScore: roundScore ?? this.roundScore,
      targetScore: targetScore ?? this.targetScore,
      ante: ante ?? this.ante,
      round: round ?? this.round,
      sortMode: sortMode ?? this.sortMode,
      jokers: jokers ?? this.jokers,
      pendingJoker: identical(pendingJoker, _copySentinel) ? this.pendingJoker : pendingJoker as JokerType?,
      lastScore: lastScore ?? this.lastScore,
      history: history + [if (saveToHistory) this],
    );
  }

  BalatroHandScore _scoreHand(List<SuitedCard> cards) {
    final base = BalatroHandScore.evaluate(cards);
    var factor = 1;
    for (final joker in jokers) {
      factor *= joker.scoreFactorFor(base.kind);
    }
    return base.withMultiplierFactor(factor);
  }

  static JokerType _randomJoker() {
    final index = Random().nextInt(JokerType.values.length);
    return JokerType.values[index];
  }

  static int rankValue(SuitedCard card) {
    final value = card.value;
    return switch (value) {
      AceSuitedCardValue() => 14,
      KingSuitedCardValue() => 13,
      QueenSuitedCardValue() => 12,
      JackSuitedCardValue() => 11,
      NumberSuitedCardValue(:final value) => value,
      _ => 0,
    };
  }

  static bool isStraight(List<int> ranks) {
    final uniqueRanks = ranks.toSet().toList()..sort();
    if (uniqueRanks.length < 5) {
      return false;
    }

    final lowAceRanks = uniqueRanks.map((rank) => rank == 14 ? 1 : rank).toList()..sort();
    return _isSequential(uniqueRanks) || _isSequential(lowAceRanks);
  }

  static bool _isSequential(List<int> ranks) {
    for (var i = 1; i < ranks.length; i++) {
      if (ranks[i] - ranks[i - 1] != 1) {
        return false;
      }
    }
    return true;
  }

  static List<SuitedCard> _sorted(List<SuitedCard> cards, HandSort mode) {
    final nextCards = [...cards];
    nextCards.sort((a, b) {
      final primary = switch (mode) {
        HandSort.rank => rankValue(a).compareTo(rankValue(b)),
        HandSort.suit => a.suit.index.compareTo(b.suit.index),
      };

      if (primary != 0) {
        return primary;
      }

      final secondary = switch (mode) {
        HandSort.rank => a.suit.index.compareTo(b.suit.index),
        HandSort.suit => rankValue(a).compareTo(rankValue(b)),
      };

      return secondary;
    });
    return nextCards;
  }
}

class Solitaire extends HookConsumerWidget {
  final Difficulty difficulty;
  final bool startWithTutorial;

  const Solitaire({
    super.key,
    required this.difficulty,
    this.startWithTutorial = false,
  });

  SolitaireState get initialState => SolitaireState.getInitialState(difficulty: difficulty);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = useState(initialState);
    final showingJokerDialog = useState(false);

    final hudKey = useMemoized(() => GlobalKey());
    final boardKey = useMemoized(() => GlobalKey());
    final handKey = useMemoized(() => GlobalKey());
    final controlsKey = useMemoized(() => GlobalKey());

    void startTutorial() {
      showGameTutorial(
        context,
        screens: [
          TutorialScreen.key(
            key: hudKey,
            message:
                'This Balatro-inspired layout keeps your run info on the left. You have 3 hands to play and 3 discards to burn through each round.',
          ),
          TutorialScreen.key(
            key: boardKey,
            message:
                'The center board shows your current blind, score target, round score, and deck progress. Reach the target score before your hands run out.',
          ),
          TutorialScreen.key(
            key: handKey,
            message:
                'Tap up to 5 cards from your hand to select them. Played hands score poker-style combinations like Pairs, Straights, and Flushes.',
          ),
          TutorialScreen.key(
            key: controlsKey,
            message:
                'Use Play Hand to score the selected cards, Discard to cycle them out, and the sort buttons to reorder your hand by rank or suit.',
          ),
        ],
      );
    }

    useOneTimeEffect(() {
      if (startWithTutorial) {
        Future.delayed(const Duration(milliseconds: 200)).then((_) => startTutorial());
      }
      return null;
    });

    useEffect(() {
      final pendingJoker = state.value.pendingJoker;
      if (pendingJoker == null || showingJokerDialog.value) {
        return null;
      }

      showingJokerDialog.value = true;
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!context.mounted) {
          showingJokerDialog.value = false;
          return;
        }

        await showDialog<void>(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => _JokerRewardDialog(
            joker: pendingJoker,
            onCollect: () {
              ref.read(audioServiceProvider).playPlace();
              state.value = state.value.collectPendingJoker();
              ref.read(achievementServiceProvider).markJokerCollected(pendingJoker);
              Navigator.of(dialogContext).pop();
            },
          ),
        );

        showingJokerDialog.value = false;
      });

      return null;
    }, [state.value.pendingJoker]);

    return CardScaffold(
      game: Game.klondike,
      difficulty: difficulty,
      onNewGame: () => state.value = initialState,
      onRestart: () => state.value = initialState,
      onTutorial: startTutorial,
      onUndo: state.value.history.isEmpty ? null : () => state.value = state.value.withUndo(),
      isVictory: state.value.isVictory,
      builder: (context, constraints, cardBack, _, __) {
        final panelColor = const Color(0xFF18242A);
        final borderColor = const Color(0xFF315F67);

        return Container(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF1B4C45),
                Color(0xFF276956),
                Color(0xFF214F43),
              ],
            ),
            borderRadius: BorderRadius.circular(24),
          ),
          child: Stack(
            children: [
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(24),
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: List.generate(
                          48,
                          (index) => index.isEven
                              ? Colors.white.withValues(alpha: 0.02)
                              : Colors.transparent,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(18),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      key: hudKey,
                      width: min(250, constraints.maxWidth * 0.26),
                      child: _BalatroSidebar(
                        state: state.value,
                        panelColor: panelColor,
                        borderColor: borderColor,
                      ),
                    ),
                    const SizedBox(width: 18),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, contentConstraints) {
                          final compactHeight = contentConstraints.maxHeight < 720;
                          final denseHeight = contentConstraints.maxHeight < 660;
                          final jokerBarHeight = denseHeight ? 64.0 : compactHeight ? 72.0 : 88.0;
                          return Column(
                            children: [
                              SizedBox(
                                height: jokerBarHeight,
                                child: _JokerBar(
                                  jokers: state.value.jokers,
                                  panelColor: panelColor,
                                  borderColor: borderColor,
                                ),
                              ),
                              SizedBox(height: denseHeight ? 6 : compactHeight ? 8 : 12),
                              Expanded(
                                flex: compactHeight ? 7 : 6,
                                child: _BalatroBoard(
                                  key: boardKey,
                                  state: state.value,
                                  cardBack: cardBack.build(),
                                  panelColor: panelColor,
                                  borderColor: borderColor,
                                ),
                              ),
                              SizedBox(height: denseHeight ? 6 : compactHeight ? 10 : 14),
                              SizedBox(
                                height: denseHeight ? 112 : compactHeight ? 132 : 150,
                                child: _BalatroHandRow(
                                  key: handKey,
                                  cards: state.value.hand,
                                  selectedCards: state.value.selectedCards,
                                  onTapCard: (card) => state.value = state.value.toggleSelection(card),
                                ),
                              ),
                              SizedBox(height: denseHeight ? 4 : compactHeight ? 8 : 10),
                              SizedBox(
                                height: denseHeight ? 72 : compactHeight ? 92 : 104,
                                child: _BalatroControls(
                                  key: controlsKey,
                                  state: state.value,
                                  compact: compactHeight,
                                  dense: denseHeight,
                                  onPlay: state.value.canPlaySelected
                                      ? () {
                                          ref.read(audioServiceProvider).playPlace();
                                          state.value = state.value.playSelected();
                                        }
                                      : null,
                                  onDiscard: state.value.canDiscardSelected
                                      ? () {
                                          ref.read(audioServiceProvider).playDraw();
                                          state.value = state.value.discardSelected();
                                        }
                                      : null,
                                  onSortRank: () => state.value = state.value.sortHand(HandSort.rank),
                                  onSortSuit: () => state.value = state.value.sortHand(HandSort.suit),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              if (state.value.isGameOver)
                Positioned.fill(
                  child: ColoredBox(
                    color: Colors.black.withValues(alpha: 0.5),
                    child: Center(
                      child: Container(
                        width: 360,
                        padding: const EdgeInsets.all(24),
                        decoration: BoxDecoration(
                          color: panelColor.withValues(alpha: 0.95),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(color: borderColor, width: 2),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'Round Failed',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 28,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'You scored ${state.value.roundScore} / ${state.value.targetScore}. Start a new run from the menu or restart to try again.',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _BalatroSidebar extends StatelessWidget {
  final SolitaireState state;
  final Color panelColor;
  final Color borderColor;

  const _BalatroSidebar({
    required this.state,
    required this.panelColor,
    required this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    final lastScore = state.lastScore;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxHeight < 760;
        final dense = constraints.maxHeight < 660;
        final gap = dense ? 8.0 : 14.0;

        return ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: IntrinsicHeight(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: dense ? 5 : 4,
                  child: _SidebarPanel(
                    panelColor: panelColor,
                    borderColor: borderColor,
                    padding: EdgeInsets.all(dense ? 10 : 14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: _SidebarMetric(
                            label: 'Score at least',
                            value: '${state.targetScore}',
                            accent: const Color(0xFFFF685A),
                            compact: compact,
                          ),
                        ),
                        SizedBox(width: dense ? 8 : 10),
                        Expanded(
                          child: _SidebarMetric(
                            label: 'Round score',
                            value: '${state.roundScore}',
                            accent: Colors.white,
                            compact: compact,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(height: gap),
                Expanded(
                  flex: dense ? 4 : 3,
                  child: _SidebarPanel(
                    panelColor: panelColor,
                    borderColor: borderColor,
                    padding: EdgeInsets.all(dense ? 10 : 14),
                    child: Row(
                      children: [
                        Expanded(
                          child: _CounterCard(
                            label: 'Hands',
                            value: '${state.handsRemaining}',
                            accent: const Color(0xFF41A7FF),
                            compact: compact,
                          ),
                        ),
                        SizedBox(width: dense ? 8 : 10),
                        Expanded(
                          child: _CounterCard(
                            label: 'Discards',
                            value: '${state.discardsRemaining}',
                            accent: const Color(0xFFFF6F61),
                            compact: compact,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(height: gap),
                SizedBox(
                  height: dense ? 68 : compact ? 78 : 90,
                  child: _CounterCard(
                    label: 'Round',
                    value: '${state.round}',
                    accent: const Color(0xFFFFB020),
                    compact: compact,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _BalatroBoard extends StatelessWidget {
  final SolitaireState state;
  final Widget cardBack;
  final Color panelColor;
  final Color borderColor;

  const _BalatroBoard({
    super.key,
    required this.state,
    required this.cardBack,
    required this.panelColor,
    required this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    final progress = state.targetScore == 0 ? 0.0 : (state.roundScore / state.targetScore).clamp(0.0, 1.0);
    return LayoutBuilder(
      builder: (context, constraints) {
        final compactHeight = constraints.maxHeight < 420;
        final denseHeight = constraints.maxHeight < 360;
        final compactWidth = constraints.maxWidth < 980;
        final deckWidth = denseHeight ? 58.0 : compactWidth ? 70.0 : 90.0;
        final boardGap = denseHeight ? 0.0 : compactHeight || compactWidth ? 2.0 : 8.0;
        final headlineSize = denseHeight ? 14.0 : compactHeight ? 16.0 : 20.0;
        final bodySize = denseHeight ? 12.0 : compactHeight ? 14.0 : 18.0;
        final compactBoard = compactHeight || compactWidth;

        return Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _TableSlot(
                    panelColor: panelColor,
                    borderColor: borderColor,
                    label: 'Blind Goal',
                    value: '${state.roundScore}/${state.targetScore}',
                    compact: compactBoard,
                    dense: denseHeight,
                  ),
                ),
                SizedBox(width: compactWidth ? 2 : 4),
                Expanded(
                  child: _TableSlot(
                    panelColor: panelColor,
                    borderColor: borderColor,
                    label: 'Selected',
                    value: '${state.selectedCards.length}/5',
                    compact: compactBoard,
                    dense: denseHeight,
                  ),
                ),
                SizedBox(width: compactWidth ? 2 : 4),
                Expanded(
                  child: _TableSlot(
                    panelColor: panelColor,
                    borderColor: borderColor,
                    label: 'Deck',
                    value: '${state.deck.length}/52',
                    compact: compactBoard,
                    dense: denseHeight,
                  ),
                ),
              ],
            ),
            SizedBox(height: boardGap),
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                      ),
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: denseHeight ? 12 : compactWidth ? 16 : 24,
                          vertical: denseHeight ? 8 : compactHeight ? 10 : 16,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Flexible(
                              child: Image.asset(
                                'assets/images/app_icon.png',
                                height: denseHeight ? 36 : compactHeight ? 46 : 68,
                                fit: BoxFit.contain,
                              ),
                            ),
                            SizedBox(height: denseHeight ? 4 : compactHeight ? 6 : 12),
                            Text(
                              state.lastScore?.name ?? 'Build your opening hand',
                              textAlign: TextAlign.center,
                              maxLines: denseHeight ? 1 : compactHeight ? 1 : 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: headlineSize,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            SizedBox(height: compactHeight ? 6 : 10),
                            Padding(
                              padding: EdgeInsets.symmetric(horizontal: denseHeight ? 4 : compactWidth ? 8 : 24),
                              child: LinearProgressIndicator(
                                value: progress,
                                minHeight: denseHeight ? 6 : compactHeight ? 8 : 12,
                                backgroundColor: Colors.white12,
                                valueColor: const AlwaysStoppedAnimation(Color(0xFF4DD29A)),
                                borderRadius: BorderRadius.circular(99),
                              ),
                            ),
                            SizedBox(height: denseHeight ? 4 : compactHeight ? 6 : 10),
                            Flexible(
                              child: Text(
                                state.hasPendingJoker
                                    ? 'Collect your new Joker before playing the next hand.'
                                    : state.isGameOver
                                        ? 'No hands left. Restart the run to try again.'
                                        : 'Reach ${state.targetScore} points before all 3 hands are spent.',
                                textAlign: TextAlign.center,
                                maxLines: denseHeight ? 1 : compactHeight ? 2 : 3,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: bodySize,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  SizedBox(width: compactWidth ? 8 : 18),
                  SizedBox(
                    width: deckWidth,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Flexible(
                          child: AspectRatio(
                            aspectRatio: 69 / 93,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(18),
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  border: Border.all(color: Colors.white, width: 2),
                                  borderRadius: BorderRadius.circular(18),
                                ),
                                child: cardBack,
                              ),
                            ),
                          ),
                        ),
                        SizedBox(height: denseHeight ? 2 : compactHeight ? 4 : 8),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            '${state.deck.length}/${state.deck.length + state.hand.length}',
                            maxLines: 1,
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: denseHeight ? 13 : compactHeight ? 15 : 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

class _BalatroHandRow extends StatelessWidget {
  final List<SuitedCard> cards;
  final Set<SuitedCard> selectedCards;
  final ValueChanged<SuitedCard> onTapCard;

  const _BalatroHandRow({
    super.key,
    required this.cards,
    required this.selectedCards,
    required this.onTapCard,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableHeight = constraints.maxHeight;
        final cardWidth = min(92.0, max(68.0, constraints.maxWidth / 7.6));
        final cardHeight = cardWidth * (124 / 92);
        final raisedOffset = max(0.0, availableHeight - cardHeight);
        final loweredOffset = min(22.0, raisedOffset);
        final totalWidth = constraints.maxWidth;
        final overlap = cards.length <= 1 ? 0.0 : min(cardWidth * 0.8, (totalWidth - cardWidth) / (cards.length - 1));
        final usedWidth = cards.isEmpty ? 0.0 : cardWidth + (cards.length - 1) * overlap;
        final start = max(0.0, (totalWidth - usedWidth) / 2);

        return Stack(
          clipBehavior: Clip.none,
          children: [
            for (var i = 0; i < cards.length; i++)
              Positioned(
                left: start + (i * overlap),
                top: selectedCards.contains(cards[i]) ? 0 : loweredOffset,
                child: _SelectableCard(
                  card: cards[i],
                  selected: selectedCards.contains(cards[i]),
                  angle: (i - ((cards.length - 1) / 2)) * 0.04,
                  width: cardWidth,
                  height: cardHeight,
                  onTap: () => onTapCard(cards[i]),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _BalatroControls extends StatelessWidget {
  final SolitaireState state;
  final bool compact;
  final bool dense;
  final VoidCallback? onPlay;
  final VoidCallback? onDiscard;
  final VoidCallback onSortRank;
  final VoidCallback onSortSuit;

  const _BalatroControls({
    super.key,
    required this.state,
    required this.compact,
    required this.dense,
    required this.onPlay,
    required this.onDiscard,
    required this.onSortRank,
    required this.onSortSuit,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compactWidth = compact || constraints.maxWidth < 760;
        final buttonWidth = dense ? 108.0 : compactWidth ? 120.0 : 140.0;
        final miniButtonWidth = dense ? 64.0 : compactWidth ? 72.0 : 82.0;
        final gap = dense ? 8.0 : compactWidth ? 10.0 : 16.0;

        return Center(
          child: Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: gap,
            runSpacing: dense ? 4 : 8,
            children: [
              _ControlButton(
                label: 'Play Hand',
                background: const Color(0xFF303841),
                enabled: onPlay != null,
                width: buttonWidth,
                compact: compactWidth,
                dense: dense,
                onPressed: onPlay,
              ),
              Container(
                padding: EdgeInsets.all(dense ? 4 : compactWidth ? 5 : 6),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.24),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Sort Hand',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: dense ? 12 : compactWidth ? 14 : 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: dense ? 4 : 6),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _MiniControlButton(
                          label: 'Rank',
                          selected: state.sortMode == HandSort.rank,
                          width: miniButtonWidth,
                          dense: dense,
                          onPressed: onSortRank,
                        ),
                        SizedBox(width: dense ? 6 : 8),
                        _MiniControlButton(
                          label: 'Suit',
                          selected: state.sortMode == HandSort.suit,
                          width: miniButtonWidth,
                          dense: dense,
                          onPressed: onSortSuit,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              _ControlButton(
                label: 'Discard',
                background: const Color(0xFF303841),
                enabled: onDiscard != null,
                width: buttonWidth,
                compact: compactWidth,
                dense: dense,
                onPressed: onDiscard,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SelectableCard extends StatelessWidget {
  final SuitedCard card;
  final bool selected;
  final double angle;
  final double width;
  final double height;
  final VoidCallback onTap;

  const _SelectableCard({
    required this.card,
    required this.selected,
    required this.angle,
    required this.width,
    required this.height,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Transform.rotate(
        angle: angle,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          width: width,
          height: height,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFFFFB020) : Colors.transparent,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              if (selected)
                BoxShadow(
                  color: const Color(0xFFFFB020).withValues(alpha: 0.35),
                  blurRadius: 18,
                  spreadRadius: 1,
                ),
            ],
          ),
          child: PlayingCardBuilder(card: card),
        ),
      ),
    );
  }
}

class _SidebarPanel extends StatelessWidget {
  final Widget child;
  final Color panelColor;
  final Color borderColor;
  final EdgeInsetsGeometry padding;

  const _SidebarPanel({
    required this.child,
    required this.panelColor,
    required this.borderColor,
    this.padding = const EdgeInsets.all(14),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: panelColor.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor, width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _SidebarBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _SidebarBadge({
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Center(
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _SidebarMetric extends StatelessWidget {
  final String label;
  final String value;
  final Color accent;
  final bool compact;

  const _SidebarMetric({
    required this.label,
    required this.value,
    required this.accent,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.all(compact ? 10 : 12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.24),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.white70,
              fontSize: compact ? 12 : 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(height: compact ? 4 : 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              maxLines: 1,
              style: TextStyle(
                color: accent,
                fontSize: compact ? 20 : 24,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CounterCard extends StatelessWidget {
  final String label;
  final String value;
  final Color accent;
  final bool compact;

  const _CounterCard({
    required this.label,
    required this.value,
    required this.accent,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 12,
        vertical: compact ? 8 : 10,
      ),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.24),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.white70,
              fontSize: compact ? 11 : 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          SizedBox(height: compact ? 2 : 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              maxLines: 1,
              style: TextStyle(
                color: accent,
                fontSize: compact ? 22 : 30,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TableSlot extends StatelessWidget {
  final String label;
  final String value;
  final Color panelColor;
  final Color borderColor;
  final bool compact;
  final bool dense;

  const _TableSlot({
    required this.label,
    required this.value,
    required this.panelColor,
    required this.borderColor,
    this.compact = false,
    this.dense = false,
  });

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return Container(
        height: dense ? 30 : 40,
        decoration: BoxDecoration(
          color: panelColor.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: borderColor.withValues(alpha: 0.8), width: 2),
        ),
        padding: EdgeInsets.symmetric(horizontal: dense ? 8 : 12, vertical: dense ? 2 : 4),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: dense ? 9 : 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            SizedBox(width: dense ? 4 : 8),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerRight,
                child: Text(
                  value,
                  maxLines: 1,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: dense ? 13 : 15,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      constraints: const BoxConstraints(minHeight: 80),
      decoration: BoxDecoration(
        color: panelColor.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: borderColor.withValues(alpha: 0.8), width: 2),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              maxLines: 1,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 25,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _JokerBar extends StatelessWidget {
  final List<JokerType> jokers;
  final Color panelColor;
  final Color borderColor;

  const _JokerBar({
    required this.jokers,
    required this.panelColor,
    required this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: panelColor.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor, width: 2),
      ),
      child: Row(
        children: [
          const Text(
            'Jokers',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: jokers.isEmpty
                ? const Text(
                    'Clear 3 rounds to earn a Joker.',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  )
                : ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: jokers.length,
                    separatorBuilder: (context, index) => const SizedBox(width: 10),
                    itemBuilder: (context, index) => _OwnedJokerCard(joker: jokers[index]),
                  ),
          ),
        ],
      ),
    );
  }
}

class _OwnedJokerCard extends StatelessWidget {
  final JokerType joker;

  const _OwnedJokerCard({
    required this.joker,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: joker.description,
      child: AspectRatio(
        aspectRatio: 63 / 95,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.asset(
            joker.assetPath,
            fit: BoxFit.cover,
          ),
        ),
      ),
    );
  }
}

class _JokerRewardDialog extends StatelessWidget {
  final JokerType joker;
  final VoidCallback onCollect;

  const _JokerRewardDialog({
    required this.joker,
    required this.onCollect,
  });

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF18242A),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: const BorderSide(color: Color(0xFF315F67), width: 2),
      ),
      title: Text(
        'New Joker',
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.w800,
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.asset(
              joker.assetPath,
              height: 120,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            joker.title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            joker.description,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        ElevatedButton(
          onPressed: onCollect,
          child: const Text('Collect Joker'),
        ),
      ],
    );
  }
}

class _ControlButton extends StatelessWidget {
  final String label;
  final Color background;
  final bool enabled;
  final double width;
  final bool compact;
  final bool dense;
  final VoidCallback? onPressed;

  const _ControlButton({
    required this.label,
    required this.background,
    required this.enabled,
    required this.width,
    required this.compact,
    required this.dense,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final compactLabel = compact || width <= 120;
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 180),
      opacity: enabled ? 1 : 0.45,
      child: SizedBox(
        width: width,
        height: dense ? 44 : compact ? 48 : 54,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: background,
            foregroundColor: Colors.white,
            textStyle: TextStyle(
              fontSize: dense ? 14 : compactLabel ? 16 : 22,
              fontWeight: FontWeight.w800,
            ),
            padding: EdgeInsets.symmetric(horizontal: dense ? 10 : 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
          ),
          onPressed: onPressed,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              maxLines: 1,
              softWrap: false,
            ),
          ),
        ),
      ),
    );
  }
}

class _MiniControlButton extends StatelessWidget {
  final String label;
  final bool selected;
  final double width;
  final bool dense;
  final VoidCallback onPressed;

  const _MiniControlButton({
    required this.label,
    required this.selected,
    required this.width,
    required this.dense,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: dense ? 30 : 38,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: selected ? const Color(0xFFFFB020) : const Color(0xFF3E414D),
          foregroundColor: selected ? Colors.black : Colors.white,
          padding: EdgeInsets.zero,
          textStyle: TextStyle(
            fontSize: dense ? 13 : 15,
            fontWeight: FontWeight.w800,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        onPressed: onPressed,
        child: Text(label),
      ),
    );
  }
}
