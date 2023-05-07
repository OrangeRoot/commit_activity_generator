import 'dart:io';
import 'dart:math';

import 'package:args/args.dart';
import 'package:uuid/uuid.dart';
import 'package:path/path.dart';

void main(List<String> args) async {
  final parser = getParser();
  ArgResults? results;
  try {
    results = parser.parse(args);
  } catch (error) {
    print(error.toString());
    return;
  }
  if (results['help']) {
    print(parser.usage);
    return;
  }
  if (results['version']) {
    print('Version: 1.0.0');
    return;
  }
  final currentDate = DateTime.now().copyWith(hour: 8, minute: 0, microsecond: 0, millisecond: 0);
  final String? repositoryOption = results['repository'];
  final String? startDateOption = results['start_date'];
  final String? endDateOption = results['end_date'];
  final String? maxCommitsOption = results['max_commits'];
  final String? coverageOption = results['coverage'];

  String? repositoryName = Uuid().v1();
  String? repositoryAddress;
  if (repositoryOption != null) {
    final regex = RegExp(
        r'^((git@)?(https:\/\/)?)?(github\.com)([:\/]?)([a-zA-Z0-9_-]+)\/([a-zA-Z0-9_-]+)\.git$');
    final match = regex.firstMatch(repositoryOption);
    if (match?.group(7) == null) {
      displayError(
          'Invalid value \'$repositoryOption\' for repository option. See --help or -h for more information.');
      return;
    }
    repositoryName = match!.group(7)!;
    repositoryAddress = 'https://${match.group(4)}/${match.group(6)}/$repositoryName.git';
  }

  DateTime? startDate = currentDate.subtract(Duration(days: 1));
  if (startDateOption != null) {
    startDate = DateTime.tryParse('$startDateOption 08:00:00');
    if (startDate == null) {
      displayError(
          'Invalid value \'$startDateOption\' for start_date option. See --help or -h for more information.');
      return;
    }
  }

  DateTime? endDate = currentDate;
  if (endDateOption != null) {
    endDate = DateTime.tryParse('$endDateOption 08:00:00');
    if (endDate == null) {
      displayError(
          'Invalid value \'$endDateOption\' for end_date option. See --help or -h for more information.');
      return;
    }
  }

  if (startDate.isAfter(endDate)) {
    displayError(
        'Invalid value \'$endDateOption\' for end_date option. See --help or -h for more information.');
    return;
  }

  int? maxCommits = 10;
  if (maxCommitsOption != null) {
    maxCommits = int.tryParse(maxCommitsOption);
    if (maxCommits == null || maxCommits < 1 || maxCommits > 600) {
      displayError(
          'Invalid value \'$maxCommitsOption\' for max_commits option. See --help or -h for more information.');
      return;
    }
  }

  int? coverage = 70;
  if (coverageOption != null) {
    coverage = int.tryParse(coverageOption);
    if (coverage == null || coverage < 1 || coverage > 100) {
      displayError(
          'Invalid value \'$coverageOption\' for coverage option. See --help or -h for more information.');
      return;
    }
  }
  try {
    await Directory(repositoryName).create();
  } catch (error) {
    print(error.toString());
    return;
  }
  Directory.current = repositoryName;

  await git(['init']);

  final daysRange = endDate.difference(startDate).inDays + 1;

  for (var i = 0; i < daysRange; i++) {
    if (Random().nextInt(100) < coverage) {
      final comPerDay = Random().nextInt(maxCommits) + 1;
      final commitTimeSpacing = (Duration(hours: 10).inMinutes / comPerDay).floor();
      for (var j = 0; j < comPerDay; j++) {
        final commitTime = startDate.add(Duration(days: i, minutes: j * commitTimeSpacing));
        await commit(commitTime);
      }
    }
    displayLoadingBar((i + 1) / daysRange);
  }

  if (repositoryAddress != null) {
    await push(repositoryAddress);
  }

  print('\n\n\x1b[32mSuccess!\x1b[0m');
}

void displayLoadingBar(double percentDone) {
  final partDone = (percentDone * 50).round();
  final partToDo = 50 - partDone;
  String loadingText = '';
  for (var i = 0; i < partDone; i++) {
    loadingText += '▓';
  }
  for (var i = 0; i < partToDo; i++) {
    loadingText += '░';
  }

  final percents = (percentDone * 100).round();
  stdout.write('$loadingText $percents%\r');
}

Future<void> commit(DateTime commitTime) async {
  await File(join(Directory.current.path, 'README.md'))
      .writeAsString('Readme: ${commitTime.toIso8601String()}');
  await git(['add', '.']);
  await git(['commit', '-m', commitTime.toIso8601String(), '--date', commitTime.toIso8601String()]);
}

Future<void> push(String repository) async {
  await git(['remote', 'add', 'origin', repository]);
  await git(['push', 'origin', 'master']);
}

Future<void> git(List<String> arguments) async {
  ProcessResult result = await Process.run('git', arguments);

  switch (result.exitCode) {
    case 128:
      displayError('''${result.stderr}
        To change targeted remote repository go to local repository folder and use:
        \t'git remote remove origin'
        \t'git remote add origin <repository_correct_address>'
        and then push it with:
        \t'git push origin master'
        ''');
      break;
    default:
      break;
  }
}

void displayError(String error) {
  print("""\x1b[91mError: $error\x1b[0m""");
}

ArgParser getParser() {
  final parser = ArgParser()
    ..addOption(
      'coverage',
      abbr: 'c',
      mandatory: false,
      help: '''Sets the percentage of days in a year when the script
performs commits. Should be between 1 and 100.
Default value: 70.''',
    )
    ..addOption(
      'end_date',
      abbr: 'e',
      mandatory: false,
      help: '''Sets the date of the last commit. Should be in format 
yyyy-mm-dd, E.g.: 1936-11-12.
Default value: today's date.''',
    )
    ..addOption(
      'max_commits',
      abbr: 'm',
      mandatory: false,
      help: '''Sets the maximum number of commits the program can
make in a day. Should be between 1 and 600.
Default value: 10.''',
    )
    ..addOption(
      'repository',
      abbr: 'r',
      mandatory: false,
      help: '''Specifies an address to an empty, non-initialized remote
git repository. If provided, the script pushes the 
changes to the specified repository. The address can be
in one of the following formats:
\t 'https://github.com/{username}/{repositoryName}.git'
\t 'git@github.com:{username}/{repositoryName}.git'
\t 'github.com/{username}/{repositoryName}.git' ''',
    )
    ..addOption(
      'start_date',
      abbr: 's',
      mandatory: false,
      help: '''Sets the date of the first commit. Should be in format
yyyy-mm-dd, E.g.: 1936-11-12
Default value: yesterday's date.''',
    )
    ..addFlag(
      'version',
      abbr: 'v',
      defaultsTo: false,
      negatable: false,
      help: '''Display this help and exit.''',
    )
    ..addFlag(
      'help',
      abbr: 'h',
      defaultsTo: false,
      negatable: false,
      help: '''Output version information and exit.''',
    );
  return parser;
}
