class MemberFieldConflict {
  final String abstractType;
  final String field;
  final String firstMember;
  final String firstType;
  final String secondMember;
  final String secondType;

  const MemberFieldConflict({
    required this.abstractType,
    required this.field,
    required this.firstMember,
    required this.firstType,
    required this.secondMember,
    required this.secondType,
  });

  String get description =>
      "'$field' is '$firstType' on '$firstMember' but '$secondType' on '$secondMember'";
}
