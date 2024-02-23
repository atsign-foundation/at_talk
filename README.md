<a href="https://atsign.com#gh-light-mode-only"><img width=250px src="https://atsign.com/wp-content/uploads/2022/05/atsign-logo-horizontal-color2022.svg#gh-light-mode-only" alt="The Atsign Foundation"></a><a href="https://atsign.com#gh-dark-mode-only"><img width=250px src="https://atsign.com/wp-content/uploads/2023/08/atsign-logo-horizontal-reverse2022-Color.svg#gh-dark-mode-only" alt="The Atsign Foundation"></a>

# atTalk 

atTalk is a very simple end-to-end-encrypted command line chat client in homage to Unix talk.

## Usage

You need to put your @<your atSign>.atKeys file in ~/.atsign/keys and then run the dart program detailing your atSign and the remote atSign you want to chat with.

e.g.

`dart pub get`

To ensure that dependencies are in place. Then:

`dart bin/at_talk.dart -a "@colin" -t "@kevin"`

The person you want to atTalk with will have to do the same but in reverse

`dart bin/at_talk.dart -a "@kevin" -t "@colin"`


## Useful things to do with atTalk beyond having a talk 

atTalk can take pipes! Yes you can pipe output to a chat session, which is a cool thing to do sometimes

`cat myfile | dart bin/at_talk.dart -a "@colin" -t "@kevin"`

or

`tail -f ~/myfile.log | dart bin/at_talk.dart -a "@colin" -t "@kevin"`

## Demo

[![asciicast](https://asciinema.org/a/nzIIKLCkMTBUOWVqKk3TckClc.svg)](https://asciinema.org/a/nzIIKLCkMTBUOWVqKk3TckClc)
