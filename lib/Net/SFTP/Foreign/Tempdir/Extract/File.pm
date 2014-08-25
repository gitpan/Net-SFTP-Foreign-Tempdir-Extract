package Net::SFTP::Foreign::Tempdir::Extract::File;
use strict;
use warnings;
use base qw{Path::Class::File};
use File::Tempdir qw{};
use Archive::Zip qw(AZ_OK); #TODO use Archive::Extract instead

our $VERSION = '0.04';

=head1 NAME

Net::SFTP::Foreign::Tempdir::Extract::File - Path::Class::File with an extract method

=head1 SYNOPSIS

  use Net::SFTP::Foreign::Tempdir::Extract;
  my $sftp=Net::SFTP::Foreign::Tempdir::Extract->new(user=>$user, match=>qr/\.zip\Z/);
  my $file=$sftp->next; # isa Net::SFTP::Foreign::Tempdir::Extract::File

=head1 DESCRIPTION

Net::SFTP::Foreign::Tempdir::Extract::File is a convince wrapper around L<Path::Class>, L<Archive::Zip> and L<File::Tempdir>

=head1 USAGE

  my $archive = Net::SFTP::Foreign::Tempdir::Extract::File->new( $path, $filename );
  my @files = $archive->extract; #array of Net::SFTP::Foreign::Tempdir::Extract::File files

=head2 extract

Extracts Zip files to temporary directory

  my @files = $archive->extract; #array of Net::SFTP::Foreign::Tempdir::Extract::File files
  my $files = $archive->extract; #array reference of Net::SFTP::Foreign::Tempdir::Extract::File files

Note: The file is temporary and will be cleaned up when the variable goes out of scope.

=cut

sub extract {
  my $self = shift;
  my $az   = Archive::Zip->new;
  unless ($az->read($self->stringify) == AZ_OK) {die(qq{Error: Cannot open file "$self".})};
  my @files=();
  foreach my $member ($az->members) {
    next if $member->isDirectory;
    my $tmpdir          = File::Tempdir->new;                 #separate tmp directory for each file for fine grained cleanup
    my $local_folder    = $tmpdir->name;
    my $name            = $member->fileName;
    my $file            = $self->new($local_folder, $name);   #isa Net::SFTP::Foreign::Tempdir::Extract::File (not -f yet)
    $file->{"__tmpdir"} = $tmpdir;                            #needed for scope clean up of File::Tempdir object
    my $status          = $az->extractMember($name, $file->stringify); #automatically creates directory structure
    die("Error: Failed to extract file $name.") unless $status == AZ_OK;
    die("Error: File $file is not readable.") unless -r $file;
    push @files, $file;
  }
  return wantarray ? @files : \@files;
}

#head2 __tmpdir
#
#property to keep the tmp directory in scope for the life of the file object
#
#cut

=head1 TODO

Support other archive formats besides zip

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

L<File::Tempdir>, L<Archive::Zip>

=cut

1;
