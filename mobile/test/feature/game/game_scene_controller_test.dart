import 'package:flutter_test/flutter_test.dart';
import 'package:four3/src/feature/game/model/game_models.dart';
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

  group('scene synchronization', () {
    const GameMove first = GameMove(
      x: 0,
      y: 0,
      z: 0,
      player: Player.one,
      index: 0,
    );
    const GameMove moved = GameMove(
      x: 4,
      y: 4,
      z: 0,
      player: Player.one,
      index: 0,
    );

    test('replaces a reused index when the move belongs to a new position', () {
      expect(
        GameSceneController.staleMoveIndices(
          existing: const [first],
          next: const [moved],
        ),
        {0},
      );
    });

    test('keeps an unchanged move and removes an absent move', () {
      const GameMove second = GameMove(
        x: 1,
        y: 1,
        z: 0,
        player: Player.two,
        index: 1,
      );
      expect(
        GameSceneController.staleMoveIndices(
          existing: const [first, second],
          next: const [first],
        ),
        {1},
      );
    });
  });

  group('xray opacity animation', () {
    test('interpolates over the same 150ms duration as the web client', () {
      expect(
        GameSceneController.opacityAt(
          from: 1,
          target: .43,
          elapsed: .075,
          animations: true,
        ),
        closeTo(.715, 1e-9),
      );
      expect(
        GameSceneController.opacityAt(
          from: 1,
          target: .43,
          elapsed: .15,
          animations: true,
        ),
        closeTo(.43, 1e-12),
      );
    });

    test('snaps when animations are disabled', () {
      expect(
        GameSceneController.opacityAt(
          from: 1,
          target: .43,
          elapsed: 0,
          animations: false,
        ),
        .43,
      );
    });
  });
}
