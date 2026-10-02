import 'package:flutter_test/flutter_test.dart';
import 'package:four3/src/feature/game/scene/game_scene_controller.dart';

void main() {
  group('pick column height', () {
    test('uses the highest visible occupied layer like the web client', () {
      expect(GameSceneController.displayedHeight(0, <int>[0, 1, 2, 3, 4]), 0);
      expect(GameSceneController.displayedHeight(3, <int>[0, 1, 2, 3, 4]), 3);
      expect(GameSceneController.displayedHeight(5, <int>[0, 1, 2, 3, 4]), 5);
      expect(GameSceneController.displayedHeight(5, <int>[0, 2, 4]), 5);
      expect(GameSceneController.displayedHeight(4, <int>[0, 2, 4]), 3);
      expect(GameSceneController.displayedHeight(5, <int>[0]), 1);
      expect(GameSceneController.displayedHeight(5, <int>[]), 0);
    });
  });

  group('piece falling animation', () {
    test('starts above the board before the first rendered frame', () {
      expect(GameSceneController.fallingOffset(0), 2.2);
      expect(GameSceneController.fallingOffset(.27), closeTo(0, 1e-9));
      expect(GameSceneController.fallingOffset(.34), closeTo(.085, 1e-9));
      expect(GameSceneController.fallingOffset(.41), 0);
    });
  });
}
