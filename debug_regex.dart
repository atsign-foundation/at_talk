import 'dart:io';

void main() {
  String key = '@eligibleassault:attalk.ai6bh@llama';
  String regex = 'attalk.ai6bh@';

  RegExp regExp = RegExp(regex);
  bool matches = regExp.hasMatch(key);

  print('Key: $key');
  print('Regex: $regex');
  print('Matches: $matches');

  // Let's also try some variations
  List<String> testRegexes = [
    'attalk.ai6bh@',
    'attalk\\.ai6bh@',
    '.*attalk\\.ai6bh.*',
    'attalk',
    'ai6bh'
  ];

  for (String testRegex in testRegexes) {
    RegExp testRegExp = RegExp(testRegex);
    bool testMatches = testRegExp.hasMatch(key);
    print('Regex "$testRegex" matches: $testMatches');
  }
}
