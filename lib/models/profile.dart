/// Profil utilisateur (cf. React getProfile → api/profile?username=).
class Profile {
  final int id;
  final String username;
  final String avatarUrl;
  final String backgroundUrl;
  final String description;
  final int nbFollowers;
  final int nbFollowing;
  final bool isFollowing;
  // Champs privés renvoyés uniquement pour son propre profil (édition)
  final String email;
  final String firstName;
  final String lastName;
  final String birthDate;

  const Profile({
    this.id = 0,
    required this.username,
    this.avatarUrl = '',
    this.backgroundUrl = '',
    this.description = '',
    this.nbFollowers = 0,
    this.nbFollowing = 0,
    this.isFollowing = false,
    this.email = '',
    this.firstName = '',
    this.lastName = '',
    this.birthDate = '',
  });

  bool get hasAvatar => avatarUrl.isNotEmpty;
  bool get hasBackground => backgroundUrl.isNotEmpty;

  factory Profile.fromJson(Map<String, dynamic> j) => Profile(
        id: (j['id'] as num?)?.toInt() ?? 0,
        username: (j['username'] ?? '').toString(),
        avatarUrl: (j['avatar_url'] ?? '').toString(),
        backgroundUrl: (j['background_url'] ?? j['background'] ?? '').toString(),
        description: (j['description'] ?? '').toString(),
        nbFollowers: (j['nb_followers'] as num?)?.toInt() ?? 0,
        nbFollowing: (j['nb_following'] as num?)?.toInt() ?? 0,
        isFollowing: j['is_following'] == true,
        email: (j['email'] ?? '').toString(),
        firstName: (j['firstName'] ?? j['first_name'] ?? '').toString(),
        lastName: (j['lastName'] ?? j['last_name'] ?? '').toString(),
        birthDate: (j['birthDate'] ?? j['birth_date'] ?? '').toString(),
      );

  Profile copyWith({bool? isFollowing, int? nbFollowers}) => Profile(
        id: id,
        username: username,
        avatarUrl: avatarUrl,
        backgroundUrl: backgroundUrl,
        description: description,
        nbFollowers: nbFollowers ?? this.nbFollowers,
        nbFollowing: nbFollowing,
        isFollowing: isFollowing ?? this.isFollowing,
      );
}
