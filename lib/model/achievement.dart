import 'package:solitaire/model/save_state.dart';

enum Achievement {
  joker1('Joker', 'Collect Joker.', 'joker1.png'),
  joker2('Jolly Joker', 'Collect Jolly Joker.', 'joker2.png'),
  joker3('Zany Joker', 'Collect Zany Joker.', 'joker3.png'),
  joker4('Mad Joker', 'Collect Mad Joker.', 'joker4.png'),
  joker5('Crazy Joker', 'Collect Crazy Joker.', 'joker5.png'),
  joker6('Droll Joker', 'Collect Droll Joker.', 'joker6.png');

  final String name;
  final String description;
  final String assetName;

  const Achievement(this.name, this.description, this.assetName);

  String get assetPath => 'assets/images/$assetName';

  int? getCurrentProgress({required SaveState saveState}) => null;
  int? getProgressMax() => null;
}
