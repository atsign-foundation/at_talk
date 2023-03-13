import 'dart:io';
import 'package:dart_periphery/dart_periphery.dart';

//#TODO better name for this class
class ExternalSigner {
  late Serial _serialPort;
  late String _customLibraryLocation;
  late String _applicationId;
  late String _privateKeyId;
  ExternalSigner();

  void init() {
    _customLibraryLocation = '/usr/lib/arm-linux-gnueabihf/libperiphery_arm.so';
    setCustomLibrary(_customLibraryLocation);
    _serialPort = Serial('/dev/ttyS0', Baudrate.b115200);
    _applicationId = 'A0000005590010';
    _privateKeyId = '303036';
    //_publicKeyId = '303037';
  }

  String getPublicKey(String publicKeyId) {
    var channelNumber;
    try {
      // Step 1. Open a logical channel. This should return a logical port  number [01|02|03] followed by [9000]. 9000 is success code.
      channelNumber = _openLogicalChannel();
      // Step 2. Select IOTsafe by application id
      _selectIOTSafeApplication(channelNumber!);
      return _readPublicKey(_serialPort, channelNumber, publicKeyId);
    } on Exception catch (e, trace) {
      print('exception during signing ${e.toString()}');
      print(trace);
      throw e;
    } finally {
      if (channelNumber != null &&
          channelNumber.startsWith(RegExp(r'01|02|03'))) {
        print('closing channel $channelNumber');
        _closeChannel(_serialPort, channelNumber);
      }
      _serialPort.setVMIN(0);
      _serialPort.dispose();
    }
  }

  String? sign(String dataHash) {
    try {
      // Step 1. Open a logical channel. This should return a logical port  number [01|02|03] followed by [9000]. 9000 is success code.
      var channelNumber = _openLogicalChannel();
      // Step 2. Select IOTsafe by application id
      _selectIOTSafeApplication(channelNumber!);

      // Step 3. Compute signature init
      _computeSignatureInit(channelNumber);

      // Step 4. Compute signature update
      _computeSignatureUpdate(channelNumber, dataHash);

      // Strp 5. Retrieve computed signature
      var signature = _retrieveSignature(channelNumber);
      return signature;
    } on Exception catch (e, trace) {
      print('exception during signing ${e.toString()}');
      print(trace);
    }
    return null;
  }

  String _readPublicKey(
      Serial serialPort, String channelNumber, String publicKeyId) {
    // INS - CD -read public key
    // P1 - 00
    // P2 - 00
    // 05 - length of command
    // 85 - public key id
    // 03 - data length
    _serialPort.writeString(
        "AT+CSIM=20, \"8${channelNumber.substring(1)}CD0000058503${publicKeyId}\"\r\n");
    var readPublicKeyResult = _serialPort.read(256, 1000);
    print('readPublicKeyResult :$readPublicKeyResult');
    bool isReadPublicKeyResultSuccess =
        _parseResult(readPublicKeyResult.toString(), ATCommand.readPublicKey);
    print('isReadPublicKeyResultSuccess $isReadPublicKeyResultSuccess');
    if (!isReadPublicKeyResultSuccess) {
      throw Exception('Read public key failure');
    }
    _serialPort.writeString(
        "AT+CSIM=10, \"8${channelNumber.substring(1)}C0000047\"\r\n");
    var retrievePublicKeyResult = _serialPort.read(256, 1000);
    var csimResult = _parseAtCsimResult(retrievePublicKeyResult.toString());
    final publicKey = _parsePublicKeyResult(csimResult);
    if (publicKey == null) {
      throw Exception('cannot read public key');
    }
    print('retrievePublicKeyResult :$publicKey');
    return publicKey;
  }

  String? _parsePublicKeyResult(AtCsimResult csimResult) {
    var commandResult = csimResult.result;
    print(commandResult);
    if (commandResult != null && commandResult.startsWith('344549438641')) {
      commandResult = commandResult.substring(12, commandResult.length - 4);
      return commandResult;
    }
    return null;
  }

  String? _openLogicalChannel() {
    final openChannelResult = _getChannelNumber(_openChannel(_serialPort));
    var channelNumber = openChannelResult.channelNumber;
    print('channelNumber:$channelNumber');
    if (openChannelResult.success) {
      return channelNumber;
    } else {
      throw Exception('open channel failed');
    }
  }

  String _openChannel(Serial serialPort) {
    print('Opening a non-default logical channel');
    serialPort.writeString('AT+CSIM=10, \"0070000000\"\r\n');
    var event = serialPort.read(256, 1000);
    final result = event.toString();
    print('openChannelResult: $result');
    return result;
  }

  void _selectIOTSafeApplication(String channelNumber) {
    _serialPort.writeString(
        "AT+CSIM=24, \"${channelNumber}A4040007${_applicationId}\"\r\n");
    var selectApplicationResult = _serialPort.read(256, 1000);
    print('selectApplicationResult :$selectApplicationResult');
    bool isValidApplication =
        _parseResult(selectApplicationResult.toString(), ATCommand.selectApp);
    print('isValidApplication $isValidApplication');
  }

  void _computeSignatureInit(String channelNumber) {
    // 2A - tag for compute signature init
    // 0F - length of command
    // 84 - private key tag
    // A1 - tag for mode of operation
    // 03 - value for mode of operation - external hash
    // 91 - tag for hash algorithm.
    // 01-  value for hash algorithm. sha256
    // 92 - tag for signature algorithm
    // 04 - value for signature algorithm. ecdsa
    _serialPort.writeString(
        "AT+CSIM=40,\"8${channelNumber.substring(1)}2A00010F8403${_privateKeyId}A1010391020001920104\"\r\n");
    var computeSignatureInitResult = _serialPort.read(256, 1000);
    print('computeSignatureInitResult :$computeSignatureInitResult');
    bool isComputeSignatureInitSuccess = _parseResult(
        computeSignatureInitResult.toString(), ATCommand.computeSignatureInit);
    print('isComputeSignatureInitSuccess: $isComputeSignatureInitSuccess');
  }

  void _computeSignatureUpdate(String channelNumber, String dataHash) {
    // 2B Tag for compute signature update
    // 80 - last incoming data_
    // 01 - session number
    // 22 - length of command
    // 9E - tag for hash
    // 20 -length of hash
    print('computing signature from external hash');
    _serialPort.writeString(
        "AT+CSIM=78,\"8${channelNumber.substring(1)}2B8001229E20$dataHash\"\r\n");
    var computeSignatureUpdateResult = '';
    // command takes a while to execute. Read until OK is received.
    while (true) {
      final readEvent = _serialPort.read(512, 1000);
      computeSignatureUpdateResult += readEvent.toString();
      if (!readEvent.toString().contains('OK')) {
        print('Got result: $computeSignatureUpdateResult');
        sleep(Duration(seconds: 2));
        continue;
      }
      break;
    }
    print(
        'computeSignatureUpdateResult ${computeSignatureUpdateResult.toString()}');
    bool isComputeSignatureSuccess = _parseComputeSignatureUpdateResult(
        computeSignatureUpdateResult.toString());
    print('isComputeSignatureSuccess :$isComputeSignatureSuccess');
  }

  String _retrieveSignature(String channelNumber) {
    _serialPort.writeString(
        "AT+CSIM=10,\"8${channelNumber.substring(1)}C0000043\"\r\n");
    var getSignatureResult = _serialPort.read(256, 1000);
    print('getSignatureResult $getSignatureResult');
    final signatureData = _parseAtCsimResult(getSignatureResult.toString());
    print('signature: ${signatureData.result}');
    var signatureStr = '';
    if (signatureData.result != null &&
        signatureData.result!.startsWith('330040')) {
      // remove start tag, length and success code at the end.
      signatureStr =
          signatureData.result!.substring(6, signatureData.result!.length - 4);
    }
    return signatureStr.toLowerCase();
  }

  OpenChannelResult _getChannelNumber(String openChannelResult) {
    final atCsimResult = _parseAtCsimResult(openChannelResult);
    if (atCsimResult.result == null ||
        atCsimResult.result!.isEmpty ||
        atCsimResult.success == false) {
      print('unexpected response from open channel: $openChannelResult');
      return OpenChannelResult(false, null);
    }
    if (atCsimResult.result!.startsWith(RegExp(r'01|02|03'))) {
      if (atCsimResult.result!.substring(2, 6) == '9000') {
        final channelNumber = atCsimResult.result!.substring(0, 2);
        print('open channel successful');
        return OpenChannelResult(true, channelNumber);
      } else {
        print(
            'open channel failed with non-success code: ${atCsimResult.result!.substring(2, 6)}');
      }
    } else {
      print(
          'open channel failed.Returned channel number : ${atCsimResult.result!.substring(0, 2)}');
      return OpenChannelResult(false, atCsimResult.result!.substring(0, 2));
    }
    return OpenChannelResult(false, null);
  }
}

bool _parseResult(String result, ATCommand atCommand) {
  final atCsimResult = _parseAtCsimResult(result);
  if (atCsimResult.result == null ||
      atCsimResult.result!.isEmpty ||
      atCsimResult.success == false) {
    print('unexpected response from ${atCommand.toString()}: $atCsimResult');
    return false;
  }
  if (atCommand == ATCommand.readPublicKey && atCsimResult.result == '6147') {
    return true;
  } else if (atCsimResult.result == '9000') {
    return true;
  } else {
    print('failure code in ${atCommand.toString()} ${atCsimResult.result}');
  }
  return false;
}

bool _parseComputeSignatureUpdateResult(String result) {
  final atCsimResult = _parseAtCsimResult(result);
  if (atCsimResult.result == null ||
      atCsimResult.result!.isEmpty ||
      atCsimResult.success == false) {
    print('unexpected response from compute signature update: $atCsimResult');
    return false;
  }
  if (atCsimResult.result == '6143') {
    return true;
  }
  return false;
}

AtCsimResult _parseAtCsimResult(String result) {
  final atCsimResult = AtCsimResult();
  if (result.isEmpty || !result.contains(AtCsimResult.pattern)) {
    print('unexpected response : $result');
    return atCsimResult;
  }
  int startIndex = result.indexOf(AtCsimResult.pattern);
  int bytesStartIndex = startIndex + AtCsimResult.pattern.length;
  int bytesEndindex = startIndex + result.substring(startIndex).indexOf(',\"');
  String bytesToRead = result.substring(bytesStartIndex, bytesEndindex);
  atCsimResult.bytesToRead = int.parse(bytesToRead);
  atCsimResult.result = result.substring(
      bytesEndindex + 2, bytesEndindex + 2 + atCsimResult.bytesToRead);
  print('atCsimResult.result ${atCsimResult.result}');
  atCsimResult.success = true;
  return atCsimResult;
}

void _closeChannel(Serial port, String channelNumber) {
  print('closing channel : $channelNumber');
  final channelCloseCommand = 'AT+CSIM=10, \"007080${channelNumber}00\"\r\n';
  print('channelCloseCommand: $channelCloseCommand');
  port.writeString(channelCloseCommand);
  final result = port.read(256, 1000);
  print('close channel result: ${result.toString()}');
}

class OpenChannelResult {
  bool success;
  String? channelNumber;

  OpenChannelResult(this.success, this.channelNumber);
}

class AtCsimResult {
  String? result;
  late int bytesToRead;
  bool success = false;
  static const String pattern = '+CSIM: ';

  @override
  String toString() {
    return 'AtCsimResult{result: $result, bytesToRead: $bytesToRead, success: $success}';
  }
}

enum ATCommand {
  openChannel,
  selectApp,
  computeSignatureInit,
  computeSignatureUpdate,
  readPublicKey
}
