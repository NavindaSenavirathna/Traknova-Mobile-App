class AuthModel {
  final String email;
  final String password;

  AuthModel({
    this.email = '',
    this.password = '',
  });

  AuthModel copyWith({
    String? email,
    String? password,
  }) {
    return AuthModel(
      email: email ?? this.email,
      password: password ?? this.password,
    );
  }
}