class AppUser {
  final int id;
  final String email;
  final String displayName;
  final String? firstName;
  final String? lastName;
  final String? phone;
  final bool profileComplete;
  final int eggBalance;
  final int level;

  const AppUser({
    required this.id,
    required this.email,
    required this.displayName,
    this.firstName,
    this.lastName,
    this.phone,
    required this.profileComplete,
    required this.eggBalance,
    required this.level,
  });

  AppUser copyWith({int? eggBalance, int? level}) => AppUser(
        id: id,
        email: email,
        displayName: displayName,
        firstName: firstName,
        lastName: lastName,
        phone: phone,
        profileComplete: profileComplete,
        eggBalance: eggBalance ?? this.eggBalance,
        level: level ?? this.level,
      );

  factory AppUser.fromJson(Map<String, dynamic> json) => AppUser(
        id: json['id'] as int,
        email: json['email'] as String,
        displayName: json['display_name'] as String,
        firstName: json['first_name'] as String?,
        lastName: json['last_name'] as String?,
        phone: json['phone'] as String?,
        profileComplete: json['profile_complete'] as bool? ?? false,
        eggBalance: json['egg_balance'] as int,
        level: json['level'] as int? ?? 1,
      );
}
