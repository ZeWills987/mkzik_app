// Utilisateur retourné par la recherche (cf. interface/User.tsx → SearchUser)
class SearchUser {
  final int id;
  final String username;
  final String avatarUrl;
  final int nbFollowers;
  final bool isFollowing;

  const SearchUser({
    required this.id,
    required this.username,
    this.avatarUrl = '',
    this.nbFollowers = 0,
    this.isFollowing = false,
  });

  factory SearchUser.fromJson(Map<String, dynamic> j) => SearchUser(
        id: (j['id'] as num?)?.toInt() ?? 0,
        username: (j['username'] ?? '').toString(),
        avatarUrl: (j['avatar_url'] ?? '').toString(),
        nbFollowers: (j['nb_followers'] as num?)?.toInt() ?? 0,
        isFollowing: j['is_following'] == true || j['is_followed'] == true,
      );

  SearchUser copyWith({bool? isFollowing}) => SearchUser(
        id: id,
        username: username,
        avatarUrl: avatarUrl,
        nbFollowers: nbFollowers,
        isFollowing: isFollowing ?? this.isFollowing,
      );
}
