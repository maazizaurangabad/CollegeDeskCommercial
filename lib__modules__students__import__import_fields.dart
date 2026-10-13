/// Student fields a spreadsheet column can be matched to.
/// Ids are stored in saved templates; never rename them.
enum ImportField {
  ignore,
  serialNo,
  fullName,
  firstName,
  middleName,
  lastName,
  altName,
  gender,
  dateOfBirth,
  placeOfBirth,
  nationality,
  motherTongue,
  category,
  caste,
  subCaste,
  bloodGroup,
  heightCm,
  weightKg,
  address,
  admissionDate,
  previousSchool,
  grNumber,
  pen,
  apaar,
  saralId,
  admissionNumber,
  aadhaar,
  className,
  divisionName,
  rollNumber,
  fatherName,
  motherName,
  guardianName,
  mobile,
  altMobile,
  email,
  notes,
}

/// Headings seen in real school sheets, in English and Marathi.
/// Compared after removing spaces, dots and symbols, ignoring case.
const Map<ImportField, List<String>> importSynonyms = {
  ImportField.serialNo: ['srno', 'sno', 'serialno', 'serial', 'srnumber', 'slno', 'अनुक्रमांक', 'अनु', 'अक्र'],
  ImportField.fullName: [
    'name', 'fullname', 'studentname', 'nameofstudent', 'nameofthestudent', 'studentsname', 'candidatename',
    'विद्यार्थ्याचेनाव', 'विद्यार्थ्याचेसंपूर्णनाव', 'नाव', 'पूर्णनाव',
  ],
  ImportField.firstName: ['firstname', 'fname', 'givenname', 'studentfirstname', 'पहिलेनाव', 'विद्यार्थ्याचेनावप्रथम'],
  ImportField.middleName: ['middlename', 'mname', 'fathersname', 'fathername', 'वडिलांचेनाव', 'मधलेनाव'],
  ImportField.lastName: ['lastname', 'lname', 'surname', 'familyname', 'आडनाव'],
  ImportField.altName: ['nameinmarathi', 'nameinurdu', 'nameinhindi', 'marathiname', 'urduname', 'मराठीनाव'],
  ImportField.gender: ['gender', 'sex', 'mf', 'लिंग'],
  ImportField.dateOfBirth: ['dob', 'dateofbirth', 'birthdate', 'birthdt', 'जन्मतारीख', 'जन्मदिनांक'],
  ImportField.placeOfBirth: ['placeofbirth', 'birthplace', 'pob', 'जन्मस्थळ', 'जन्मठिकाण'],
  ImportField.nationality: ['nationality', 'राष्ट्रीयत्व'],
  ImportField.motherTongue: ['mothertongue', 'मातृभाषा'],
  ImportField.category: ['category', 'cat', 'castecategory', 'प्रवर्ग', 'संवर्ग'],
  ImportField.caste: ['caste', 'जात'],
  ImportField.subCaste: ['subcaste', 'subcast', 'पोटजात'],
  ImportField.bloodGroup: ['bloodgroup', 'bg', 'blood', 'रक्तगट'],
  ImportField.heightCm: ['height', 'heightcm', 'उंची'],
  ImportField.weightKg: ['weight', 'weightkg', 'वजन'],
  ImportField.address: ['address', 'residentialaddress', 'permanentaddress', 'पत्ता'],
  ImportField.admissionDate: ['admissiondate', 'dateofadmission', 'doa', 'प्रवेशदिनांक', 'प्रवेशतारीख'],
  ImportField.previousSchool: ['previousschool', 'lastschool', 'lastschoolattended', 'previouscollege', 'पूर्वीचीशाळा', 'मागीलशाळा'],
  ImportField.grNumber: ['grno', 'gr', 'grnumber', 'generalregister', 'generalregisterno', 'regno', 'registerno', 'जनरलरजिस्टरक्रमांक', 'जीआरक्र'],
  ImportField.pen: ['pen', 'penno', 'pennumber', 'permanenteducationnumber'],
  ImportField.apaar: ['apaar', 'apaarid', 'apar', 'aparid', 'abcid'],
  ImportField.saralId: ['saral', 'saralid', 'studentid', 'सरलआयडी'],
  ImportField.admissionNumber: ['admissionno', 'admno', 'admissionnumber', 'प्रवेशक्रमांक'],
  ImportField.aadhaar: ['aadhaar', 'aadhar', 'aadhaarno', 'aadharno', 'uid', 'uidno', 'आधार', 'आधारक्रमांक'],
  ImportField.className: ['class', 'std', 'standard', 'course', 'program', 'classname', 'इयत्ता', 'वर्ग'],
  ImportField.divisionName: ['division', 'div', 'section', 'batch', 'तुकडी'],
  ImportField.rollNumber: ['rollno', 'roll', 'rollnumber', 'rno', 'हजेरीक्रमांक', 'रोलनं'],
  ImportField.fatherName: ['fatherfullname', 'nameoffather', 'fathersfullname', 'वडिलांचेपूर्णनाव'],
  ImportField.motherName: ['mothername', 'mothersname', 'nameofmother', 'आईचेनाव'],
  ImportField.guardianName: ['guardianname', 'parentname', 'पालकाचेनाव'],
  ImportField.mobile: ['mobile', 'mobileno', 'mob', 'mobno', 'contact', 'contactno', 'phone', 'phoneno', 'parentmobile', 'fathermobile', 'मोबाईल', 'मोबाईलक्रमांक', 'संपर्क'],
  ImportField.altMobile: ['altmobile', 'alternatemobile', 'mobile2', 'mothermobile', 'othermobile'],
  ImportField.email: ['email', 'emailid', 'mail', 'ईमेल'],
  ImportField.notes: ['remarks', 'remark', 'notes', 'note', 'शेरा'],
};

/// Header text in the form used for matching: lower case, letters and digits only.
String normalizeHeader(String header) =>
    header.toLowerCase().replaceAll(RegExp(r'[^a-z0-9\u0900-\u097F\u0600-\u06FF]'), '');

/// Best guess for one column heading; [ImportField.ignore] when unsure.
ImportField guessField(String header) {
  final h = normalizeHeader(header);
  if (h.isEmpty) return ImportField.ignore;
  for (final entry in importSynonyms.entries) {
    if (entry.value.contains(h)) return entry.key;
  }
  // Looser: the heading starts with a known word, e.g. "Mobile No. (Father)".
  for (final entry in importSynonyms.entries) {
    for (final word in entry.value) {
      if (word.length >= 4 && h.startsWith(word)) return entry.key;
    }
  }
  return ImportField.ignore;
}

/// Guesses every column, never assigning the same field twice
/// (the first matching column wins; later ones are left as "Ignore").
List<ImportField> guessMapping(List<String> headers) {
  final used = <ImportField>{};
  return [
    for (final h in headers)
      () {
        final f = guessField(h);
        if (f == ImportField.ignore || used.contains(f)) return ImportField.ignore;
        used.add(f);
        return f;
      }(),
  ];
}

/// The header row: the first of the top 15 rows where at least three cells
/// look like known headings, else the first row with three or more filled cells.
int guessHeaderRow(List<List<String>> rows) {
  final limit = rows.length < 15 ? rows.length : 15;
  for (var r = 0; r < limit; r++) {
    final known = rows[r].where((c) => guessField(c) != ImportField.ignore).length;
    if (known >= 3) return r;
  }
  for (var r = 0; r < limit; r++) {
    if (rows[r].where((c) => c.trim().isNotEmpty).length >= 3) return r;
  }
  return 0;
}
