package SeqWare::Schedule::Ini;
# A class to deal with ini file creation via template

use common::sense;
use Template;
use Data::Dumper;
use Config::Simple;
use File::Spec;

sub new {
    my $class = shift;
    my $self = bless {}, $class;
    return $self;
}

sub create_ini_file {
    my $self = shift;
    my ($output_dir,
	$template,
	$data,
	$donor_id) = @_;

    my $def = {};
    my $tt = Template->new(ABSOLUTE => 1);

    # make a working dir
    system("mkdir -p $output_dir") unless -d $output_dir;
    $output_dir .= "/$donor_id";
    system("mkdir -p $output_dir") unless -d $output_dir;

    # make an ini file
    say "Making ini file at $output_dir/workflow.ini";
    $tt->process(File::Spec->rel2abs($template), $data, File::Spec->rel2abs("$output_dir/workflow.ini")) || die $tt->error;
}


sub create_settings_file {
    my $self = shift;
    my (
        $donor,
        $seqware_settings_file,
        $url,
        $username,
        $password,
        $output_dir,
        $center_name) = @_;

    my $settings = new Config::Simple($seqware_settings_file);

    $url //= '<SEQWARE URL>';
    $username //= '<SEQWARE USER NAME>';
    $password //= '<SEQWARE PASSWORD>';

    $settings->param('SW_REST_URL', $url);
    $settings->param('SW_REST_USER', $username);
    $settings->param('SW_REST_PASS',$password);

    my $donor_id = $donor->{donor_id};
    say "Making settings file at $output_dir/settings";
    $settings->write("$output_dir/settings");
}



1;
