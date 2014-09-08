package Net::SFTP::Foreign::Tempdir::Extract;
use strict;
use warnings;
use base qw{Package::New};
use File::Tempdir qw{};
use Net::SFTP::Foreign qw{};
use Net::SFTP::Foreign::Tempdir::Extract::File;

our $VERSION = '0.06';

=head1 NAME

Net::SFTP::Foreign::Tempdir::Extract - Secure FTP client integrating Path::Class, Tempdir, and Archive Extraction

=head1 SYNOPSIS

  use Net::SFTP::Foreign::Tempdir::Extract;
  my $sftp=Net::SFTP::Foreign::Tempdir::Extract->new(
                           user   => $user,
                           match  => qr/\.zip\Z/,
                           backup => "./backup", #default is not to backup
                           delete => 1,          #default is not to delete
                          );
  my $file=$sftp->next;

=head1 DESCRIPTION

Secure FTP client which downloads files locally to a temp directory for operations and automatically cleans up all temp files after variables are out of scope.

=head1 USAGE

=head2 File Downloader

This is a simple file downloader implementation

  use Net::SFTP::Foreign::Tempdir::Extract;
  my $sftp=Net::SFTP::Foreign::Tempdir::Extract->new(host=>$host, user=>$user);
  my $file=$sftp->download($folder, $filename);

=head2 File Watcher

This is a simple file watcher implementation

  use Net::SFTP::Foreign::Tempdir::Extract;
  my $sftp=Net::SFTP::Foreign::Tempdir::Extract->new(host=>"myserver", user=>"myaccount", match=>qr/\.zip\Z/, folder=>"/myfolder");
  my $file=$sftp->next or exit; #nothing to process so exit
  print "$file";                #process file here

=head2 Subclass

This is a typical subclass implementation for a particular infrastructure

  package My::SFTP;
  use base qw{Net::SFTP::Foreign::Tempdir::Extract};
  sub host   {"myserver.mydomain.tld"};
  sub folder {"/myfolder"};
  sub match  {qr/\Amyfile\.zip\Z/};
  sub backup {time};
  sub delete (1);
  1;

=head1 CONSTRUCTOR

=head2 new

=head1 METHODS

=head2 download

Downloads the named file in the folder.

  my $file=$sftp->download("remote_file.zip");                   #isa Net::SFTP::Foreign::Tempdir::Extract::File
  my $file=$sftp->download("/remote_folder", "remote_file.zip"); #  which isa Path::Class::File object with an extract method

=cut

sub download {
  my $self   = shift;
  my $sftp   = $self->sftp;
  my $remote = pop or die("Error: filename required.");
  my $folder = shift || $self->folder;
  my $tmpdir  = File::Tempdir->new    or die("Error: Could not create File::Tempdir object");
  my $local_folder = $tmpdir->name    or die("Error: Temporary directory not configured.");
  $sftp->setcwd($folder)              or die(sprintf("Error: %s", $sftp->error));
  $sftp->mget($remote, $local_folder) or die(sprintf("Error: %s", $sftp->error));
  my $file=Net::SFTP::Foreign::Tempdir::Extract::File->new($local_folder => $remote);
  die("Error: Could not read $file.") unless -r $file;
  $file->{"__tmpdir"}=$tmpdir; #must keep tmpdir scope alive
  my $backup=$self->backup;
  if ($backup) {
    $sftp->mkpath($backup)                    or die("Error: Cannot create backup directory");
    $sftp->rename($remote, "$backup/$remote") or die("Error: Cannot rename remote file $remote to $backup/$remote");
  } elsif ($self->delete) {
    $sftp->remove($remote)                    or warn("Warning: Cannot delete remote file $remote");
  }
  return $file;
}

=head2 next

Downloads the next file in list and saves it locally to a temporary folder. Returns a L<Path::Class::File> object or undef if there are no more files.

=cut

sub next {
  my $self=shift;
  my $list=$self->list;
  if (@$list) {
    my $file=shift @$list;
    #print Dumper($file);
    return $self->download($file);
  } else {
    return;
  }
}

=head2 list

Returns list of filenames that match the folder and regular expression

Note: List is shifted for each call to next method

=cut

sub list {
  my $self=shift;
  $self->{"list"}=shift if @_;
  unless (defined($self->{"list"})) {
    #printf "%s: Listing files in folder: %s\n", DateTime->now, $self->folder;
    $self->{"list"}=$self->sftp->ls($self->folder,
                                    wanted     => $self->match,
                                    ordered    => 1,
                                    no_wanted  => qr/\A\.{1,2}\Z/,
                                    names_only => 1,
                                   );
    #print Dumper $self->{"list"};
  }
  return wantarray ? @{$self->{"list"}} : $self->{"list"};
}

=head1 PROPERTIES

=head2 host

SFTP server host name.

=cut

sub host {
  my $self=shift;
  $self->{"host"}=shift if @_;
  $self->{"host"}=$self->_host_default unless defined($self->{"host"});
  return $self->{"host"};
}

sub _host_default {
  return "";
}

=head2 user

SFTP user name (defaults to current user)

=cut

sub user {
  my $self=shift;
  $self->{"user"}=shift if @_;
  return $self->{"user"};
}

=head2 folder

Folder on remote SFTP server.

Note: Some SFTP servers put clients in a change rooted environment.

=cut

sub folder {
  my $self=shift;
  $self->{"folder"}=shift if @_;
  $self->{"folder"}=$self->_folder_default unless defined $self->{"folder"};
  return $self->{"folder"};
}

sub _folder_default {
  return "/incoming";
}

=head2 match

Regular Expression to match file names for the next iterator

=cut

sub match {
  my $self=shift;
  $self->{"match"}=shift if @_;
  $self->{"match"}=$self->_match_default unless defined($self->{"match"});
  return $self->{"match"};
}

sub _match_default {
  return qr/.*/;
}

=head2 backup

Sets or returns the backup folder property.

=cut

sub backup {
  my $self=shift;
  $self->{"backup"}=shift if @_;
  $self->{"backup"}="" unless defined($self->{"backup"});
  return $self->{"backup"};
}

=head2 delete

Sets or returns the delete boolean property.

=cut

sub delete {
  my $self=shift;
  $self->{"delete"}=shift if @_;
  $self->{"delete"}=0 unless defined($self->{"delete"});
  return $self->{"delete"};
}

=head1 OBJECT ACCESSORS

=head2 sftp

Returns a cached connected L<Net::SFTP::Foreign> object

=cut

sub sftp {
  my $self=shift;
  unless (defined $self->{"sftp"}) {
    my %params      = ();
    $params{"host"} = $self->host or die("Error: host required");
    $params{"user"} = $self->user if $self->user; #not required
    my $sftp        = Net::SFTP::Foreign->new(%params);
    die(sprintf("Error: Connecting to %s: %s", $params{"host"}, $sftp->error)) if $sftp->error;
    $self->{"sftp"} = $sftp;
  }
  return $self->{"sftp"};
}

=head1 BUGS

Send email to author and log on RT.

=head1 SUPPORT

DavisNetworks.com supports all Perl applications including this package.

=head1 AUTHOR

  Michael R. Davis
  CPAN ID: MRDVT
  Satellite Tracking of People, LLC
  mdavis@stopllc.com
  http://www.stopllc.com/

=head1 COPYRIGHT

This program is free software; you can redistribute it and/or modify it under the same terms as Perl itself.

The full text of the license can be found in the LICENSE file included with this module.

=head1 SEE ALSO

=head2 Building Blocks

L<Path::Class::File>, L<Net::SFTP::Foreign>, L<File::Tempdir>

=cut

1;
