/// Starting structures offered in the setup wizard. After setup they are
/// ordinary rows the institution can rename, add to or delete.
enum StructureTemplate { juniorCollege, school, coaching, blank }

class TemplateProgram {
  const TemplateProgram(this.name, {this.stream, this.divisions = const ['A'], this.next});

  final String name;
  final String? stream;
  final List<String> divisions;

  /// Name of the class students are promoted to.
  final String? next;
}

class TemplateStructure {
  const TemplateStructure({required this.programs, this.programLabel, this.divisionLabel});

  final List<TemplateProgram> programs;
  final String? programLabel;
  final String? divisionLabel;
}

TemplateStructure structureFor(StructureTemplate template) {
  switch (template) {
    case StructureTemplate.juniorCollege:
      return const TemplateStructure(programs: [
        TemplateProgram('11th Science', stream: 'Science', next: '12th Science'),
        TemplateProgram('11th Commerce', stream: 'Commerce', next: '12th Commerce'),
        TemplateProgram('11th Arts', stream: 'Arts', next: '12th Arts'),
        TemplateProgram('12th Science', stream: 'Science'),
        TemplateProgram('12th Commerce', stream: 'Commerce'),
        TemplateProgram('12th Arts', stream: 'Arts'),
      ]);
    case StructureTemplate.school:
      const names = ['1st', '2nd', '3rd', '4th', '5th', '6th', '7th', '8th', '9th', '10th'];
      return TemplateStructure(programs: [
        for (var i = 0; i < names.length; i++)
          TemplateProgram(names[i], next: i + 1 < names.length ? names[i + 1] : null),
      ]);
    case StructureTemplate.coaching:
      return const TemplateStructure(
        programLabel: 'Course',
        divisionLabel: 'Batch',
        programs: [
          TemplateProgram('JEE', divisions: ['Batch 1']),
          TemplateProgram('NEET', divisions: ['Batch 1']),
        ],
      );
    case StructureTemplate.blank:
      return const TemplateStructure(programs: []);
  }
}
