import 'dart:math';

/// Index du titre suivant dans la liste d'origine, en boucle.
///
/// En mode aléatoire : un autre titre tiré au hasard (le même seulement s'il est
/// seul). Un [current] inconnu (< 0) donne le premier titre, ou n'importe lequel
/// en aléatoire.
int nextSourceIndex({
  required int length,
  required int current,
  required bool shuffle,
  Random? random,
}) {
  if (length <= 1) return 0;
  if (!shuffle) return (current + 1) % length;
  final rng = random ?? Random();
  if (current < 0 || current >= length) return rng.nextInt(length);
  final r = rng.nextInt(length - 1); // 0 .. length-2
  return r >= current ? r + 1 : r;
}

/// Index du titre précédent dans la liste d'origine, en boucle.
int previousSourceIndex({required int length, required int current}) {
  if (length <= 1) return 0;
  return current <= 0 ? length - 1 : current - 1;
}
