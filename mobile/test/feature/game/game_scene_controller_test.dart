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
}
