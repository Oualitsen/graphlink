abstract class BasicEntity {
	String get id;
	Map<String, dynamic> toJson();
	static BasicEntity fromJson(Map<String, dynamic> json) {
		var typename = json['__typename'] as String;
		switch(typename) {
			case 'User': return User.fromJson(json);
			case 'Animal': return Animal.fromJson(json);
			default: throw ArgumentError("Invalid type $typename. $typename does not implement BasicEntity or not defined");
		}
	}

}

class User implements BasicEntity {

	final String id;
	final String name;

	User({required this.id, required this.name});

	Map<String, dynamic> toJson() {
		return {
			'id': id,
			'name': name
		};
	}

	static User fromJson(Map<String, dynamic> json) {
		return User(
			id: json['id'] as String,
			name: json['name'] as String
		);
	}

}

class Animal implements BasicEntity {

	final String id;
	final String name;
	final String ownerId;

	Animal({required this.id, required this.name, required this.ownerId});

	Map<String, dynamic> toJson() {
		return {
			'id': id,
			'name': name,
			'ownerId': ownerId
		};
	}

	static Animal fromJson(Map<String, dynamic> json) {
		return Animal(
			id: json['id'] as String,
			name: json['name'] as String,
			ownerId: json['ownerId'] as String
		);
	}

}

