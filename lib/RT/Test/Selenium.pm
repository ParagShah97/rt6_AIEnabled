# BEGIN BPS TAGGED BLOCK {{{
#
# COPYRIGHT:
#
# This software is Copyright (c) 1996-2023 Best Practical Solutions, LLC
#                                          <sales@bestpractical.com>
#
# (Except where explicitly superseded by other copyright notices)
#
#
# LICENSE:
#
# This work is made available to you under the terms of Version 2 of
# the GNU General Public License. A copy of that license should have
# been provided with this software, but in any event can be snarfed
# from www.gnu.org.
#
# This work is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA
# 02110-1301 or visit their web page on the internet at
# http://www.gnu.org/licenses/old-licenses/gpl-2.0.html.
#
#
# CONTRIBUTION SUBMISSION POLICY:
#
# (The following paragraph is not intended to limit the rights granted
# to you to modify and distribute this software under the terms of
# the GNU General Public License and is only of importance to you if
# you choose to contribute your changes and enhancements to the
# community by submitting them to Best Practical Solutions, LLC.)
#
# By intentionally submitting any modifications, corrections or
# derivatives to this work, or any other work intended for use with
# Request Tracker, to Best Practical Solutions, LLC, you confirm that
# you are the copyright holder for those contributions and you grant
# Best Practical Solutions,  LLC a nonexclusive, worldwide, irrevocable,
# royalty-free, perpetual, license to use, copy, create derivative
# works based on those contributions, and sublicense and distribute
# those contributions and any derivatives thereof.
#
# END BPS TAGGED BLOCK }}}

package RT::Test::Selenium;

use strict;
use warnings;

our @ISA;

sub Init {
    $ENV{RT_TEST_SELENIUM_DRIVER} ||= 'Firefox';
    my $base_class = "Test::Selenium::$ENV{RT_TEST_SELENIUM_DRIVER}";
    if ( RT::StaticUtil::RequireModule($base_class) ) {
        @ISA = $base_class;
        return 1;
    }
    RT::Test::plan( skip_all => 'No selenium' );
    return 0;
}


sub new {
    my $class = shift;
    $class->Init unless @ISA;

    my %args = (
        'extra_capabilities' => {
            'goog:chromeOptions' => {
                'args' => ['headless'],
            },
            'moz:firefoxOptions' => {
                'args' => ['-headless'],
            },
        },
        @_,
    );

    my $self = $class->SUPER::new(%args);
    $self->set_window_size( 1080, 1920 );
    $self->set_implicit_wait_timeout(2000);
    return $self;
}

sub get_ok {
    my $self = shift;
    my $url  = shift;
    if ( $url =~ s!^/!! ) {
        $url = $self->rt_base_url . $url;
    }

    local $Test::Builder::Level = $Test::Builder::Level + 1;
    $self->SUPER::get_ok( $url, @_ ? @_ : $url );
}

sub rt_base_url {
    return $RT::Test::existing_server if $RT::Test::existing_server;
    return "http://localhost:" . RT->Config->Get('WebPort') . RT->Config->Get('WebPath') . "/";
}

sub login {
    my $self = shift;
    my $user = shift || 'root';
    my $pass = shift || 'password';
    my %args = @_;

    $self->logout if $args{logout};
    local $Test::Builder::Level = $Test::Builder::Level + 1;
    $self->get_ok( $self->rt_base_url );
    $self->logged_in_as( $user, $pass );
    return 1;
}

sub logged_in_as {
    my $self = shift;
    my $user = shift || '';
    my $pass = shift || '';

    local $Test::Builder::Level = $Test::Builder::Level + 1;

    $self->submit_form_ok(
        {
            form_name => 'login',
            fields    => {
                user => $user,
                pass => $pass,
            }
        },
        "Login as $user"
    );

    if ( $user =~ /\@/ ) {
        my $user_object = RT::User->new( RT->SystemUser );
        $user_object->LoadByEmail($user);
        if ( $user_object->Id ) {
            $user = $user_object->Name;
        }
    }

    $self->body_text_like( qr/Logged in as $user/i, 'Logged in' );
    return 1;
}

sub logout {
    my $self = shift;

    # Ideally we can move the mouse to "Logged in as ..." and then click logout.
    # Sadly that "move_to" is executed lazily due to limitations in the Webdriver 3 API :/
    #
    # $self->move_to(element => $self->find_element(q{//a[@id='preferences']}));
    # $self->click_element_ok( q{//a[text()='Logout']}, '', 'Click logout button' );

    local $Test::Builder::Level = $Test::Builder::Level + 1;
    my $logout = $self->find_element(q{//a[text()='Logout']});
    $self->get_ok( $logout->get_property('href') );
    $self->body_text_unlike( qr/Logged in as/i, 'Logged out' );
    return 1;
}

sub goto_ticket {
    my $self = shift;
    my $id   = shift;
    my $view = shift || 'Display';
    unless ( $id && int $id ) {
        Test::More::diag( "error: wrong id " . defined $id ? $id : '(undef)' );
        return 0;
    }

    my $url = $self->rt_base_url;
    $url .= "Ticket/${ view }.html?id=$id";
    local $Test::Builder::Level = $Test::Builder::Level + 1;
    $self->get_ok($url);
    return 1;
}

sub goto_create_ticket {
    my $self  = shift;
    my $queue = shift;

    my $id;
    if ( ref $queue ) {
        $id = $queue->id;
    }
    elsif ( $queue =~ /^\d+$/ ) {
        $id = $queue;
    }
    else {
        my $queue_obj = RT::Queue->new( RT->SystemUser );
        my ( $ok, $msg ) = $queue_obj->Load($queue);
        die "Unable to load queue '$queue': $msg" if !$ok;
        $id = $queue_obj->id;
    }

    local $Test::Builder::Level = $Test::Builder::Level + 1;
    my ($button) = $self->find_elements(q{//input[@value='Create new ticket']});
    $self->get_ok( $self->rt_base_url ) unless $button;

    $self->click_element_ok( q{//input[@value='Create new ticket']}, '', 'Click create new ticket' );
    $self->wait_for_htmx;

    my $queue_input = $self->find_element(q{//form[@name='TicketCreate']//*[@name='Queue']});
    $self->set_select_field( 'form[name=TicketCreate] [name=Queue]', $id );
    $self->wait_for_htmx;

    return 1;
}

sub set_richtext_field {
    my $self  = shift;
    my $id    = shift;
    my $value = shift;
    $self->find_element(qq{//div[\@id='cke_$id']});
    my $script = q{
       CKEDITOR.instances[arguments[0]].setData(arguments[1]);
    };
    $self->execute_script( $script, $id, $value );
}

sub set_select_field {
    my $self     = shift;
    my $selector = shift;
    my $value    = shift;
    my $script   = q{
        const element = document.querySelector(arguments[0]);
        if ( element.value != arguments[1] ) {
            element.value = arguments[1];
            element.dispatchEvent(new Event('change'));
        }
    };
    $self->execute_script( $script, $selector, $value );
}

sub wait_for_htmx {
    my $self = shift;

    # Wait for spinner to hide
    $self->find_element(q{//div[@id='hx-boost-spinner'][@class='d-none']});

    # Wait for main container to be swapped
    $self->find_element(q{//div[@class='main-container']});
}

sub submit_form_ok {
    my $self = shift;
    my $args = shift;
    my $desc = shift || 'Submit form';

    local $Test::Builder::Level = $Test::Builder::Level + 1;
    my $xpath_prefix = $args->{form_name} ? qq{//form[\@name='$args->{form_name}']} : '';
    for my $field ( sort keys %{ $args->{fields} || {} } ) {
        my $xpath = qq{$xpath_prefix//*[\@name='$field']};
        if ( my $element = $self->find_element($xpath) ) {
            my $tag   = $element->get_tag_name;
            my $value = $args->{fields}{$field};
            if ( $tag eq 'select' ) {
                $self->set_select_field(
                    'form' . ( $args->{form_name} ? qq{[name='$args->{form_name}']} : '' ) . qq{ [name='$field']},
                    $value );
            }
            elsif ( $tag eq 'textarea' && $element->get_attribute( 'class', 1 ) =~ /\brichtext\b/ ) {
                $self->set_richtext_field( $field, $value );
            }
            elsif ( $element->get_attribute( 'type', 1 ) eq 'radio' ) {
                $self->find_element( $xpath . qq{[\@value='$value']} )->set_selected;
            }
            elsif ( $element->get_attribute( 'type', 1 ) eq 'checkbox' ) {
                for my $element ( $self->find_elements($xpath) ) {
                    my $v = $element->get_attribute( 'value', 1 );
                    if ( grep { $v eq $_ } ref $value ? @$value : $value ) {
                        $element->set_selected unless $element->is_selected;
                    }
                    else {
                        $element->toggle if $element->is_selected;
                    }
                }
            }
            else {
                $self->clear_element_ok( $xpath, $value, "Clear $field" );
                $self->type_element_ok( $xpath, $value, "Type $field" );
            }
        }
        else {
            RT->Logger->warning("Could not find field $field");
        }
    }

    # In some cases(like ticket people page), there is a hidden duplicated submit button at the beginning of the form,
    # so hitting enter on inputs triggers it. The hidden one can't be clicked, so we need to find the visible one.
    my $button;
    if ( $args->{button} ) {
        ($button)
            = grep { $_->is_displayed } $self->find_elements(qq{$xpath_prefix//input[\@name='$args->{button}']});
    }
    else {
        ($button) = grep { $_->is_displayed } $self->find_elements(qq{$xpath_prefix//input[\@type='submit']});
    }

    if ( !$button ) {
        Test::More::ok( 0, "No submit button: $desc" );
        return;
    }

    $button->click;
    $self->wait_for_htmx;
    Test::More::ok( 1, $desc );
    return 1;
}

sub follow_link_ok {
    my $self = shift;
    my $args = shift;
    my $desc = shift;

    my $xpath = '//a';
    if ( $args->{text} ) {
        $xpath .= "[text()='$args->{text}']";
    }
    elsif ( $args->{id} ) {
        $xpath .= "[\@id='$args->{id}']";
    }

    local $Test::Builder::Level = $Test::Builder::Level + 1;
    $self->click_element_ok( $xpath, '', $desc || "Click link $xpath" );
    return 1;
}

*text_like     = \&Test::Selenium::Remote::Driver::body_text_like;
*text_unlike   = \&Test::Selenium::Remote::Driver::body_text_unlike;
*text_contains = \&Test::Selenium::Remote::Driver::body_text_contains;
*text_lacks    = \&Test::Selenium::Remote::Driver::body_text_lacks;

1;
