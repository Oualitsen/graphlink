// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'inputs.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

AgencyInput _$AgencyInputFromJson(Map<String, dynamic> json) => AgencyInput(
      id: json['id'] as String?,
      designation: json['designation'] as String?,
      cashierId: json['cashierId'] as String?,
      address: json['address'] as String?,
      phones:
          (json['phones'] as List<dynamic>).map((e) => e as String).toList(),
      email: json['email'] as String?,
      webSite: json['webSite'] as String?,
    );

Map<String, dynamic> _$AgencyInputToJson(AgencyInput instance) =>
    <String, dynamic>{
      'id': instance.id,
      'designation': instance.designation,
      'cashierId': instance.cashierId,
      'address': instance.address,
      'phones': instance.phones,
      'email': instance.email,
      'webSite': instance.webSite,
    };

CashierInput _$CashierInputFromJson(Map<String, dynamic> json) => CashierInput(
      id: json['id'] as String?,
      code: json['code'] as String?,
      designation: json['designation'] as String?,
      address: json['address'] as String?,
      phones:
          (json['phones'] as List<dynamic>).map((e) => e as String).toList(),
      emails:
          (json['emails'] as List<dynamic>).map((e) => e as String).toList(),
      webSite:
          (json['webSite'] as List<dynamic>).map((e) => e as String).toList(),
    );

Map<String, dynamic> _$CashierInputToJson(CashierInput instance) =>
    <String, dynamic>{
      'id': instance.id,
      'code': instance.code,
      'designation': instance.designation,
      'address': instance.address,
      'phones': instance.phones,
      'emails': instance.emails,
      'webSite': instance.webSite,
    };

PersonalInfoInput _$PersonalInfoInputFromJson(Map<String, dynamic> json) =>
    PersonalInfoInput(
      id: json['id'] as String?,
      firstName: json['firstName'] as String,
      lastName: json['lastName'] as String,
      gender: $enumDecode(_$GenderEnumMap, json['gender']),
      dateOfBirth: json['dateOfBirth'] as int,
      placeOfBirth: json['placeOfBirth'] as String?,
      bloodGroup: $enumDecodeNullable(_$BloodGroupEnumMap, json['bloodGroup']),
      image: json['image'] as String?,
      address: json['address'] as String?,
      phones:
          (json['phones'] as List<dynamic>).map((e) => e as String).toList(),
      emails:
          (json['emails'] as List<dynamic>).map((e) => e as String).toList(),
    );

Map<String, dynamic> _$PersonalInfoInputToJson(PersonalInfoInput instance) =>
    <String, dynamic>{
      'id': instance.id,
      'firstName': instance.firstName,
      'lastName': instance.lastName,
      'gender': _$GenderEnumMap[instance.gender]!,
      'dateOfBirth': instance.dateOfBirth,
      'placeOfBirth': instance.placeOfBirth,
      'bloodGroup': _$BloodGroupEnumMap[instance.bloodGroup],
      'image': instance.image,
      'address': instance.address,
      'phones': instance.phones,
      'emails': instance.emails,
    };

const _$GenderEnumMap = {
  Gender.MAN: 'MAN',
  Gender.WOMAN: 'WOMAN',
};

const _$BloodGroupEnumMap = {
  BloodGroup.A_POSITIF: 'A_POSITIF',
  BloodGroup.A_NEGATIF: 'A_NEGATIF',
  BloodGroup.B_POSITIF: 'B_POSITIF',
  BloodGroup.B_NEGATIF: 'B_NEGATIF',
  BloodGroup.AB_POSITIF: 'AB_POSITIF',
  BloodGroup.AB_NEGATIF: 'AB_NEGATIF',
  BloodGroup.O_POSITIF: 'O_POSITIF',
  BloodGroup.O_NEGATIF: 'O_NEGATIF',
};

PatientInput _$PatientInputFromJson(Map<String, dynamic> json) => PatientInput(
      id: json['id'] as String?,
      personalInfo: json['personalInfo'] == null
          ? null
          : PersonalInfoInput.fromJson(
              json['personalInfo'] as Map<String, dynamic>),
      patientStatus:
          $enumDecodeNullable(_$PatientStatusEnumMap, json['patientStatus']),
      admissionDate: json['admissionDate'] as int,
      ensurer: json['ensurer'] == null
          ? null
          : EnsurerInput.fromJson(json['ensurer'] as Map<String, dynamic>),
      assignment: json['assignment'] == null
          ? null
          : AssignmentInput.fromJson(
              json['assignment'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$PatientInputToJson(PatientInput instance) =>
    <String, dynamic>{
      'id': instance.id,
      'personalInfo': instance.personalInfo,
      'patientStatus': _$PatientStatusEnumMap[instance.patientStatus],
      'admissionDate': instance.admissionDate,
      'ensurer': instance.ensurer,
      'assignment': instance.assignment,
    };

const _$PatientStatusEnumMap = {
  PatientStatus.PERMANANTE: 'PERMANANTE',
};

HemodialysisGroupInput _$HemodialysisGroupInputFromJson(
        Map<String, dynamic> json) =>
    HemodialysisGroupInput(
      id: json['id'] as String?,
      creationDate: json['creationDate'] as int?,
      lastUpdate: json['lastUpdate'] as int?,
      code: json['code'] as String?,
      designation: json['designation'] as String?,
      daysOfWeek: (json['daysOfWeek'] as List<dynamic>)
          .map((e) => e as String)
          .toList(),
    );

Map<String, dynamic> _$HemodialysisGroupInputToJson(
        HemodialysisGroupInput instance) =>
    <String, dynamic>{
      'id': instance.id,
      'creationDate': instance.creationDate,
      'lastUpdate': instance.lastUpdate,
      'code': instance.code,
      'designation': instance.designation,
      'daysOfWeek': instance.daysOfWeek,
    };

AssignmentInput _$AssignmentInputFromJson(Map<String, dynamic> json) =>
    AssignmentInput(
      id: json['id'] as String?,
      medicalStaff: json['medicalStaff'] == null
          ? null
          : EnsurerInput.fromJson(json['medicalStaff'] as Map<String, dynamic>),
      hemodialysisGroup: json['hemodialysisGroup'] == null
          ? null
          : HemodialysisGroupInput.fromJson(
              json['hemodialysisGroup'] as Map<String, dynamic>),
      position: json['position'] == null
          ? null
          : PositionInput.fromJson(json['position'] as Map<String, dynamic>),
      patientRoom: json['patientRoom'] == null
          ? null
          : PatientRoomInput.fromJson(
              json['patientRoom'] as Map<String, dynamic>),
      DateOfFirstIronTreatment: json['DateOfFirstIronTreatment'] as int?,
      DateOfFirstEPOTreatment: json['DateOfFirstEPOTreatment'] as int?,
      DateOfTheFirstHemodialysisSession:
          json['DateOfTheFirstHemodialysisSession'] as int?,
    );

Map<String, dynamic> _$AssignmentInputToJson(AssignmentInput instance) =>
    <String, dynamic>{
      'id': instance.id,
      'medicalStaff': instance.medicalStaff,
      'hemodialysisGroup': instance.hemodialysisGroup,
      'position': instance.position,
      'patientRoom': instance.patientRoom,
      'DateOfFirstIronTreatment': instance.DateOfFirstIronTreatment,
      'DateOfFirstEPOTreatment': instance.DateOfFirstEPOTreatment,
      'DateOfTheFirstHemodialysisSession':
          instance.DateOfTheFirstHemodialysisSession,
    };

PatientRoomInput _$PatientRoomInputFromJson(Map<String, dynamic> json) =>
    PatientRoomInput(
      id: json['id'] as String?,
      code: json['code'] as String?,
      name: json['name'] as String?,
      designation: json['designation'] as String?,
    );

Map<String, dynamic> _$PatientRoomInputToJson(PatientRoomInput instance) =>
    <String, dynamic>{
      'id': instance.id,
      'code': instance.code,
      'name': instance.name,
      'designation': instance.designation,
    };

PositionInput _$PositionInputFromJson(Map<String, dynamic> json) =>
    PositionInput(
      id: json['id'] as String?,
      designation: json['designation'] as String?,
      startTime: json['startTime'] as int?,
      endTime: json['endTime'] as int?,
    );

Map<String, dynamic> _$PositionInputToJson(PositionInput instance) =>
    <String, dynamic>{
      'id': instance.id,
      'designation': instance.designation,
      'startTime': instance.startTime,
      'endTime': instance.endTime,
    };

EnsurerInput _$EnsurerInputFromJson(Map<String, dynamic> json) => EnsurerInput(
      id: json['id'] as String?,
      person: json['person'] == null
          ? null
          : PersonalInfoInput.fromJson(json['person'] as Map<String, dynamic>),
      socialSecurityNumber: json['socialSecurityNumber'] as String?,
      ensurerRelationship: $enumDecodeNullable(
          _$EnsurerRelationshipEnumMap, json['ensurerRelationship']),
    );

Map<String, dynamic> _$EnsurerInputToJson(EnsurerInput instance) =>
    <String, dynamic>{
      'id': instance.id,
      'person': instance.person,
      'socialSecurityNumber': instance.socialSecurityNumber,
      'ensurerRelationship':
          _$EnsurerRelationshipEnumMap[instance.ensurerRelationship],
    };

const _$EnsurerRelationshipEnumMap = {
  EnsurerRelationship.PATIENT: 'PATIENT',
  EnsurerRelationship.CHILD: 'CHILD',
  EnsurerRelationship.ANCESTOR: 'ANCESTOR',
  EnsurerRelationship.PARTNER: 'PARTNER',
  EnsurerRelationship.OTHER: 'OTHER',
};

PageInfo _$PageInfoFromJson(Map<String, dynamic> json) => PageInfo(
      page: json['page'] as int,
      size: json['size'] as int,
    );

Map<String, dynamic> _$PageInfoToJson(PageInfo instance) => <String, dynamic>{
      'page': instance.page,
      'size': instance.size,
    };

MedicalStaffInput _$MedicalStaffInputFromJson(Map<String, dynamic> json) =>
    MedicalStaffInput(
      id: json['id'] as String?,
      PersonalInfo: json['PersonalInfo'] == null
          ? null
          : PersonalInfoInput.fromJson(
              json['PersonalInfo'] as Map<String, dynamic>),
      rank: $enumDecodeNullable(_$RankEnumMap, json['rank']),
    );

Map<String, dynamic> _$MedicalStaffInputToJson(MedicalStaffInput instance) =>
    <String, dynamic>{
      'id': instance.id,
      'PersonalInfo': instance.PersonalInfo,
      'rank': _$RankEnumMap[instance.rank],
    };

const _$RankEnumMap = {
  Rank.DOCTOR: 'DOCTOR',
  Rank.NURSE: 'NURSE',
  Rank.TECHNICIAN: 'TECHNICIAN',
};
