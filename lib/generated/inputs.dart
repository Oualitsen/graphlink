  import 'package:json_annotation/json_annotation.dart';
  import 'enums.dart';
  part 'inputs.g.dart';

    @JsonSerializable()
      class AgencyInput {
          final String? id;
          final String? designation;
          final String? cashierId;
          final String? address;
          final List<String> phones;
          final String? email;
          final String? webSite;
          
          AgencyInput({required this.id, required this.designation, required this.cashierId, required this.address, required this.phones, required this.email, required this.webSite});
          
          factory AgencyInput.fromJson(Map<String, dynamic> json) => _$AgencyInputFromJson(json);
          
          Map<String, dynamic> toJson() => _$AgencyInputToJson(this);
      }

    @JsonSerializable()
      class CashierInput {
          final String? id;
          final String? code;
          final String? designation;
          final String? address;
          final List<String> phones;
          final List<String> emails;
          final List<String> webSite;
          
          CashierInput({required this.id, required this.code, required this.designation, required this.address, required this.phones, required this.emails, required this.webSite});
          
          factory CashierInput.fromJson(Map<String, dynamic> json) => _$CashierInputFromJson(json);
          
          Map<String, dynamic> toJson() => _$CashierInputToJson(this);
      }

    @JsonSerializable()
      class PersonalInfoInput {
          final String? id;
          final String firstName;
          final String lastName;
          final Gender gender;
          final int dateOfBirth;
          final String? placeOfBirth;
          final BloodGroup? bloodGroup;
          final String? image;
          final String? address;
          final List<String> phones;
          final List<String> emails;
          
          PersonalInfoInput({required this.id, required this.firstName, required this.lastName, required this.gender, required this.dateOfBirth, required this.placeOfBirth, required this.bloodGroup, required this.image, required this.address, required this.phones, required this.emails});
          
          factory PersonalInfoInput.fromJson(Map<String, dynamic> json) => _$PersonalInfoInputFromJson(json);
          
          Map<String, dynamic> toJson() => _$PersonalInfoInputToJson(this);
      }

    @JsonSerializable()
      class PatientInput {
          final String? id;
          final PersonalInfoInput? personalInfo;
          final PatientStatus? patientStatus;
          final int admissionDate;
          final EnsurerInput? ensurer;
          final AssignmentInput? assignment;
          
          PatientInput({required this.id, required this.personalInfo, required this.patientStatus, required this.admissionDate, required this.ensurer, required this.assignment});
          
          factory PatientInput.fromJson(Map<String, dynamic> json) => _$PatientInputFromJson(json);
          
          Map<String, dynamic> toJson() => _$PatientInputToJson(this);
      }

    @JsonSerializable()
      class HemodialysisGroupInput {
          final String? id;
          final int? creationDate;
          final int? lastUpdate;
          final String? code;
          final String? designation;
          final List<String> daysOfWeek;
          
          HemodialysisGroupInput({required this.id, required this.creationDate, required this.lastUpdate, required this.code, required this.designation, required this.daysOfWeek});
          
          factory HemodialysisGroupInput.fromJson(Map<String, dynamic> json) => _$HemodialysisGroupInputFromJson(json);
          
          Map<String, dynamic> toJson() => _$HemodialysisGroupInputToJson(this);
      }

    @JsonSerializable()
      class AssignmentInput {
          final String? id;
          final EnsurerInput? medicalStaff;
          final HemodialysisGroupInput? hemodialysisGroup;
          final PositionInput? position;
          final PatientRoomInput? patientRoom;
          final int? DateOfFirstIronTreatment;
          final int? DateOfFirstEPOTreatment;
          final int? DateOfTheFirstHemodialysisSession;
          
          AssignmentInput({required this.id, required this.medicalStaff, required this.hemodialysisGroup, required this.position, required this.patientRoom, required this.DateOfFirstIronTreatment, required this.DateOfFirstEPOTreatment, required this.DateOfTheFirstHemodialysisSession});
          
          factory AssignmentInput.fromJson(Map<String, dynamic> json) => _$AssignmentInputFromJson(json);
          
          Map<String, dynamic> toJson() => _$AssignmentInputToJson(this);
      }

    @JsonSerializable()
      class PatientRoomInput {
          final String? id;
          final String? code;
          final String? name;
          final String? designation;
          
          PatientRoomInput({required this.id, required this.code, required this.name, required this.designation});
          
          factory PatientRoomInput.fromJson(Map<String, dynamic> json) => _$PatientRoomInputFromJson(json);
          
          Map<String, dynamic> toJson() => _$PatientRoomInputToJson(this);
      }

    @JsonSerializable()
      class PositionInput {
          final String? id;
          final String? designation;
          final int? startTime;
          final int? endTime;
          
          PositionInput({required this.id, required this.designation, required this.startTime, required this.endTime});
          
          factory PositionInput.fromJson(Map<String, dynamic> json) => _$PositionInputFromJson(json);
          
          Map<String, dynamic> toJson() => _$PositionInputToJson(this);
      }

    @JsonSerializable()
      class EnsurerInput {
          final String? id;
          final PersonalInfoInput? person;
          final String? socialSecurityNumber;
          final EnsurerRelationship? ensurerRelationship;
          
          EnsurerInput({required this.id, required this.person, required this.socialSecurityNumber, required this.ensurerRelationship});
          
          factory EnsurerInput.fromJson(Map<String, dynamic> json) => _$EnsurerInputFromJson(json);
          
          Map<String, dynamic> toJson() => _$EnsurerInputToJson(this);
      }

    @JsonSerializable()
      class PageInfo {
          final int page;
          final int size;
          
          PageInfo({required this.page, required this.size});
          
          factory PageInfo.fromJson(Map<String, dynamic> json) => _$PageInfoFromJson(json);
          
          Map<String, dynamic> toJson() => _$PageInfoToJson(this);
      }

    @JsonSerializable()
      class MedicalStaffInput {
          final String? id;
          final PersonalInfoInput? PersonalInfo;
          final Rank? rank;
          
          MedicalStaffInput({required this.id, required this.PersonalInfo, required this.rank});
          
          factory MedicalStaffInput.fromJson(Map<String, dynamic> json) => _$MedicalStaffInputFromJson(json);
          
          Map<String, dynamic> toJson() => _$MedicalStaffInputToJson(this);
      }

