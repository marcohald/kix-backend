use warnings;

use Cwd;
use lib cwd();
use lib cwd() . '/Kernel/cpan-lib';
use lib cwd() . '/plugins';
use lib cwd() . '/scripts/test/api/Cucumber';

use LWP::UserAgent;
use HTTP::Request;
use JSON::XS qw(encode_json decode_json);
use JSON::Validator;

use Test::More;
use Test::BDD::Cucumber::StepFile;

use Data::Dumper;

use Kernel::System::ObjectManager;

$Kernel::OM = Kernel::System::ObjectManager->new();

# require our helper
require '_Helper.pl';

# require our common library
require '_StepsLib.pl';
#require './_StepsLib.pl';

# feature specific steps

When qr/I query the collection of (\w+) with roleid (\d+)$/, sub {
   ( S->{Response}, S->{ResponseContent} ) = _OPTION(
      Token => S->{Token},
      URL   => S->{API_URL}.'/system/roles/'.$2.'/'.$1,
      Sort  => 'Permission.ID:numeric'
   );
};

