import 'package:flutter/material.dart';
import 'package:json_annotation/json_annotation.dart';
import 'package:solitaire/model/achievement.dart';
import 'package:solitaire/styles/color_library.dart';
import 'package:solitaire/styles/playing_card_asset_bundle_cache.dart';
import 'package:vector_graphics/vector_graphics.dart';

@JsonEnum()
enum CardBack {
  redStripes(assetName: 'back', fallbackColor: ColorLibrary.red400),
  stoneStripes(assetName: 'back', fallbackColor: ColorLibrary.stone400, achievementLock: Achievement.joker1),
  skyStripes(assetName: 'back', fallbackColor: ColorLibrary.sky400, achievementLock: Achievement.joker2),
  violetStripes(assetName: 'back', fallbackColor: ColorLibrary.violet400),
  redPoly(assetName: 'red-poly', fallbackColor: ColorLibrary.red400, achievementLock: Achievement.joker3),
  stonePoly(assetName: 'stone-poly', fallbackColor: ColorLibrary.stone400, achievementLock: Achievement.joker4),
  skyPoly(assetName: 'sky-poly', fallbackColor: ColorLibrary.sky400, achievementLock: Achievement.joker5),
  violetPoly(
    assetName: 'violet-poly',
    fallbackColor: ColorLibrary.violet400,
    achievementLock: Achievement.joker6,
  ),
  redSteps(assetName: 'red-steps', fallbackColor: ColorLibrary.red400),
  stoneSteps(assetName: 'stone-steps', fallbackColor: ColorLibrary.stone400),
  skySteps(assetName: 'sky-steps', fallbackColor: ColorLibrary.sky400),
  violetSteps(assetName: 'violet-steps', fallbackColor: ColorLibrary.violet400);

  final String assetName;
  final Color fallbackColor;
  final Achievement? achievementLock;

  const CardBack({required this.assetName, required this.fallbackColor, this.achievementLock});

  Widget build() => switch (this) {
        CardBack.redStripes ||
        CardBack.stoneStripes ||
        CardBack.skyStripes ||
        CardBack.violetStripes =>
          _colorStripeBack(),
        _ => _vectorImage(),
      };

  Widget _colorStripeBack() => VectorGraphic(
        loader: PlayingCardAssetBundleCache.getCardBackLoader(this),
        fit: BoxFit.cover,
        colorFilter: ColorFilter.mode(fallbackColor, BlendMode.lighten),
        placeholderBuilder: (_) => ColoredBox(color: fallbackColor),
      );

  Widget _vectorImage() => VectorGraphic(
        loader: PlayingCardAssetBundleCache.getCardBackLoader(this),
        fit: BoxFit.cover,
        placeholderBuilder: (_) => ColoredBox(color: fallbackColor),
      );
}
