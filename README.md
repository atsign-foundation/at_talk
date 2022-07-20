<img width=250px src="https://atsign.dev/assets/img/atPlatform_logo_gray.svg?sanitize=true">

# atTalk 

atTalk is a very simple end to end encrypted command line chat client in hommage to Unix talk.

## Usage

You need to put you @<your atsign>.atKeys file in ~/.atsign/keys and then run the dart program detailing your and the remote atSign you want to chat with.

e.g.

`dart bin/at_talk.dart -a "@colin" -t "@kevin"`

The person who want to atTalk with will have to do the same but in reverse

`dart bin/at_talk.dart -a "@kevin" -t "@colin"`


## Useful things to do with atTalk beyond having a talk 

atTalk can take pipes! Yes you can pipe output to a chat session, which is a cool then to do sometimes

`cat myfile | dart bin/at_talk.dart -a "@colin" -t "@kevin"`

or

`tail -f ~/myfile.log | dart bin/at_talk.dart -a "@colin" -t "@kevin"`
