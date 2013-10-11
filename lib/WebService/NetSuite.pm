package WebService::NetSuite;

use strict;
use warnings;

use Moose;
use Carp;
use SOAP::Lite;    # ( +trace => 'all' );
use Data::Dumper;
use XML::Parser;
use XML::Parser::EasyTree;
$XML::Parser::EasyTree::Noempty = 1;

use Crypt::OpenSSL::RSA;
use Encode;

use WebService::NetSuite::Config;

our $VERSION = '0.02';

our $version        = "2013_1";
our $sandbox_nshost = "https://webservices.sandbox.netsuite.com";
our $prod_nshost    = "https://webservices.netsuite.com";

our $sso_href  = 'https://%s/app/site/backend/sitesso.nl';
our $cart_href = 'http://%s/app/site/backend/additemtocart.nl';

our $sandbox_shopping = 'shopping.sandbox.netsuite.com';
our $prod_shopping    = 'shopping.netsuite.com';

our $sandbox_checkout = 'checkout.sandbox.netsuite.com';
our $prod_checkout    = 'checkout.netsuite.com';

has 'time'            => ( is => 'rw', required => 0 );
has 'company'         => ( is => 'ro', required => 0 );
has 'rsa_private_key' => ( is => 'ro', required => 0 );
has 'nsemail'         => ( is => 'ro', required => 1 );
has 'nspassword'      => ( is => 'ro', required => 1 );
has 'nsrole'          => ( is => 'ro', required => 0, default => 3 );
has 'nsaccount'       => ( is => 'ro', required => 1 );
has 'sandbox'         => ( is => 'ro', required => 0, default => 1 );
has 'site_id'         => ( is => 'ro', required => 0, default => 1 );

has 'record_namespaces' => (
    is       => 'ro',
    required => 1,
    default  => \&WebService::NetSuite::Config::RecordNamespaces
);

has 'search_namespaces' => (
    is       => 'ro',
    required => 1,
    default  => \&WebService::NetSuite::Config::SearchNamespaces
);

has 'record_types' => (
    is       => 'ro',
    required => 1,
    default  => \&WebService::NetSuite::Config::RecordTypes
);

has 'search_types' => (
    is       => 'ro',
    required => 1,
    default  => \&WebService::NetSuite::Config::SearchTypes
);

has 'record_fields' => (
    is       => 'ro',
    required => 1,
    default  => \&WebService::NetSuite::Config::RecordFields
);

has 'sso_href' => (
    is       => 'ro',
    required => 1,
    lazy     => 1,
    default  => sub {
        my $self = shift;
        my $href = sprintf( $sso_href,
            ( $self->sandbox == 1 )
            ? $sandbox_checkout
            : $prod_checkout );
        return $href;
    }
);

has 'cart_href' => (
    is       => 'ro',
    required => 1,
    lazy     => 1,
    default  => sub {
        my $self = shift;
        my $href = sprintf( $cart_href,
            ( $self->sandbox == 1 ) ? $sandbox_shopping : $prod_shopping );
        return $href;
    }
);

has 'soap' => (
    is       => 'ro',
    required => 1,
    lazy     => 1,
    default  => sub {
        my $self = shift;
        my $nshost = ( $self->sandbox == 1 ) ? $sandbox_nshost : $prod_nshost;

        my $soap = SOAP::Lite->new;
        $soap->proxy("$nshost/services/NetSuitePort_$version");

        my $systemNamespaces = &WebService::NetSuite::Config::SystemNamespaces;
        for my $mapping ( keys %{$systemNamespaces} ) {
            $soap->serializer->register_ns( $systemNamespaces->{$mapping},
                $mapping );
        }
        return $soap;
    }
);

sub getRequest {
    my $self = shift;
    return $self->{LAST_REQ};
}

sub getResponse {
    my $self = shift;
    return $self->{LAST_RES};
}

sub getBody {
    my $self = shift;
    return $self->{LAST_BODY};
}

sub getHead {
    my $self = shift;
    return $self->{LAST_HEAD};
}

sub getSelectValue {
    my ( $self, $recordType ) = @_;

    $self->soap->on_action( sub { return 'getSelectValue'; } );
    my $som = $self->soap->getSelectValue( $self->_passport,
        SOAP::Data->name('fieldName')->attr( { 'fieldType' => $recordType } ) );

    if ( $som->fault ) { $self->error; }
    else {
        if (
            $som->match('//getSelectValueResponse/getSelectValueResult/status')
          )
        {
            if (
                $som->dataof(
                    '//getSelectValueResponse/getSelectValueResult/status'
                )->attr->{'isSuccess'} eq 'true'
              )
            {
                my $response = $self->_parseResponse;
                if ( $response->{statusIsSuccess} eq 'true' ) {
                    $self->{GET_RESULTS} = $response;
                    return 1;
                }
                else { $self->error; }
            }
            else { $self->error; }
        }
        else { $self->error; }
    }

}

sub getCustomization {
    my ( $self, $recordType ) = @_;

    $self->soap->on_action( sub { return 'getCustomization'; } );
    my $som = $self->soap->getCustomization( $self->_passport,
        SOAP::Data->name('customizationType')
          ->attr( { 'getCustomizationType' => $recordType } ) );

    if ( $som->fault ) { $self->error; }
    else {
        if (
            $som->match(
                '//getCustomizationResponse/getCustomizationResult/status'
            )
          )
        {
            if (
                $som->dataof(
                    '//getCustomizationResponse/getCustomizationResult/status'
                )->attr->{'isSuccess'} eq 'true'
              )
            {
                my $response = $self->_parseResponse;
                if ( $response->{statusIsSuccess} eq 'true' ) {
                    $self->{GET_RESULTS} = $response;
                    return 1;
                }
                else { $self->error; }
            }
            else { $self->error; }
        }
        else { $self->error; }
    }

}

sub get {
    my ( $self, $recordType, $recordInternalId ) = @_;

    $self->soap->on_action( sub { return 'get'; } );
    my $som = $self->soap->get(
        $self->_passport,
        SOAP::Data->name('baseRef')->attr(
            {
                'internalId' => $recordInternalId,
                'type'       => $recordType,
                'xsi:type'   => 'core:RecordRef'
            }
        )->prefix('messages')
    );

    if ( $som->fault ) { $self->error; }
    else {
        if ( $som->match("//getResponse/readResponse/status") ) {
            if ( $som->dataof("//getResponse/readResponse/status")
                ->attr->{'isSuccess'} eq 'true' )
            {
                my $response = $self->_parseResponse;
                if ( $response->{statusIsSuccess} eq 'true' ) {
                    $self->{GET_RESULTS} = $response;
                    return 1;
                }
                else { $self->error; }
            }
            else { $self->error; }
        }
        else { $self->error; }
    }
}

sub getResults {
    my $self = shift;
    if   ( defined $self->{GET_RESULTS} ) { return $self->{GET_RESULTS}; }
    else                                  { return; }
}

sub search {
    my ( $self, $type, $request, $header ) = @_;

    $header->{bodyFieldsOnly} = 'true'
      if !defined $header->{bodyFieldsOnly};

    $header->{pageSize} = 10 if !defined $header->{pageSize};

    croak 'Non HASH reference passed to subroutine search!'
      if ref $request ne 'HASH';

    if ( $type !~ /Search$/ ) { $type = ucfirst($type) . 'Search'; }

    my @searchRecord;
    for my $searchType ( keys %{$request} ) {

        # basic, customerJoin

        my $searchSystemNamespace;
        my $searchTypeNamespace;
        if ( defined $self->record_types->{$type}->{$searchType} ) {
            $searchTypeNamespace = $self->record_types->{$type}->{$searchType};

        }
        else {
            croak "Search type $searchType is not defined in a $type search";
        }

        my @searchTypes;
        for my $searchElement ( @{ $request->{$searchType} } ) {

            # parent, firstName, lastName

            my $searchValue;
            $searchElement->{prefix} = 'common';
            if ( $searchElement->{attr}->{internalId} ) {
                $searchElement->{attr}->{'xsi:type'} = 'core:RecordRef';
                push @searchTypes, SOAP::Data->new( %{$searchElement} );
                next;
            }
            else {

                my $searchElementType =
                  $self->search_types->{$searchTypeNamespace}
                  ->{ $searchElement->{name} };

                $searchElement->{attr}->{'xsi:type'} =
                  'core:' . $searchElementType;

                if (    $searchElementType eq 'SearchDateField'
                    and $searchElement->{value} =~ /^\D+$/ )
                {
                    $searchValue->{name} = 'predefinedSearchValue';
                }
            }

            if ( ref $searchElement->{value} eq 'ARRAY' ) {    # customFieldList

                my @searchValues;
                for my $searchValue ( @{ $searchElement->{value} } )
                {                                              # customField

                    if ( ref $searchValue->{value} eq 'ARRAY' ) {
                        my @customFieldValues;
                        for my $customFieldValue ( @{ $searchValue->{value} } )
                        {
                            $customFieldValue->{prefix} = 'core'
                              if !defined $customFieldValue->{prefix};
                            $customFieldValue->{name} = 'searchValue'
                              if !defined $customFieldValue->{name};
                            push @customFieldValues,
                              SOAP::Data->new( %{$customFieldValue} );
                        }
                        $searchValue->{value} =
                          \SOAP::Data->value(@customFieldValues);
                        push @searchValues, SOAP::Data->new( %{$searchValue} );
                    }
                    else {
                        $searchValue->{prefix} = 'core'
                          if !defined $searchValue->{prefix};
                        $searchValue->{name} = 'searchValue'
                          if !defined $searchValue->{name};
                        if ( $searchValue->{name} eq 'customField' ) {
                            my $customFieldValue = {
                                name   => 'searchValue',
                                value  => $searchValue->{value},
                                prefix => 'core'
                            };
                            $searchValue->{value} =
                              \SOAP::Data->new( %{$customFieldValue} );
                        }
                        else {
                            if ( $searchValue->{attr}->{internalId} ) {
                                $searchValue->{attr}->{'xsi:type'} =
                                  'core:RecordRef';
                            }
                        }
                        push @searchValues, SOAP::Data->new( %{$searchValue} );
                    }
                }
                $searchElement->{value} = \SOAP::Data->value(@searchValues);
                push @searchTypes, SOAP::Data->new( %{$searchElement} );
            }
            else {
                $searchValue->{name} = 'searchValue'
                  if !defined $searchValue->{name};

                $searchValue->{value} = $searchElement->{value}
                  if !defined $searchValue->{value};

                $searchValue->{prefix} = 'core'
                  if !defined $searchValue->{prefix};

                $searchValue->{attr}->{'xsi:type'} = 'core:RecordRef'
                  if $searchElement->{attr}->{internalId};

                $searchElement->{value} =
                  \SOAP::Data->new( %{$searchValue} );

                push @searchTypes, SOAP::Data->new( %{$searchElement} );
            }
        }

        push @searchRecord,
          SOAP::Data->name( $searchType => \SOAP::Data->value(@searchTypes) )
          ->attr(
            {
                'xsi:type' => 'common:' . $searchTypeNamespace
            }
          );

    }

    $self->soap->on_action( sub { return 'search'; } );
    my $som = $self->soap->search(
        $self->_passport,
        SOAP::Header->name(
            'searchPreferences' => \SOAP::Header->value(
                SOAP::Header->name('bodyFieldsOnly')
                  ->value( $header->{bodyFieldsOnly} )->prefix('messages'),
                SOAP::Header->name('pageSize')->value( $header->{pageSize} )
                  ->prefix('messages'),
            )
          )->prefix('messages'),
        SOAP::Data->name(
            'searchRecord' => \SOAP::Data->value(@searchRecord)
          )->attr(
            {
                'xsi:type' => $self->search_namespaces->{$type} . ':' . $type
            }
          )
    );
    # $DB::single = 1;
    if ( $som->fault ) {
        die $som->fault->{faultstring};
    }
    else {
        if ( $som->match("//searchResponse/searchResult/status") ) {
            if ( $som->dataof("//searchResponse/searchResult/status")
                ->attr->{'isSuccess'} eq 'true' )
            {
                my $response = $self->_parseResponse;
                if ( $response->{statusIsSuccess} eq 'true' ) {
                    $self->{SEARCH_RESULTS} = $response;
                    return 1;
                }
                else {
                    die "request unsuccessful: " . Dumper($response);
                }
            }
            else {
                my $code = $som->dataof("//searchResponse/searchResult/status/statusDetail/code")->value;
                my $msg = $som->dataof("//searchResponse/searchResult/status/statusDetail/message")->value;
                die "request unsuccessful, code '$code', message '$msg'";
            }
        }
        else {
            die "request unsuccessful: " . Dumper($som);
        }
    }

}

sub searchResults {
    my $self = shift;
    if ( defined $self->{SEARCH_RESULTS} ) {
        return $self->{SEARCH_RESULTS};
    }
    else { return; }
}

sub searchMore {
    my ( $self, $pageIndex ) = @_;

    $self->soap->on_action( sub { return 'searchMore'; } );
    my $som =
      $self->soap->searchMore( $self->_passport,
        SOAP::Data->name('pageIndex')->value($pageIndex)->prefix('messages') );

    if ( $som->fault ) { $self->error; }
    else {
        if ( $som->match("//searchMoreResponse/searchResult/status") ) {
            if ( $som->dataof("//searchMoreResponse/searchResult/status")
                ->attr->{'isSuccess'} eq 'true' )
            {
                my $response = $self->_parseResponse;
                $self->{SEARCH_RESULTS} = $response;
                if ( $response->{statusIsSuccess} eq 'true' ) {
                    return 1;
                }
                else { $self->error; }
            }
            else { $self->error; }
        }
        else { $self->error; }
    }

}

sub searchNext {
    my $self = shift;

    $self->soap->on_action( sub { return 'searchNext'; } );
    my $som = $self->soap->searchNext;

    if ( $som->fault ) { $self->error; }
    else {
        if ( $som->match("//searchNextResponse/searchResult/status") ) {
            if ( $som->dataof("//searchNextResponse/searchResult/status")
                ->attr->{'isSuccess'} eq 'true' )
            {
                my $response = $self->_parseResponse;
                $self->{SEARCH_RESULTS} = $response;
                if ( $response->{statusIsSuccess} eq 'true' ) {
                    return 1;
                }
                else { $self->error; }
            }
            else { $self->error; }
        }
        else { $self->error; }
    }

}

sub delete {
    my ( $self, $recordType, $recordInternalId ) = @_;

    $self->soap->on_action( sub { return 'delete'; } );
    my $som = $self->soap->delete(
        $self->_passport,
        SOAP::Data->name('baseRef')->attr(
            {
                'internalId' => $recordInternalId,
                'type'       => $recordType,
                'xsi:type'   => 'core:RecordRef'
            }
        )
    );

    if ( $som->fault ) { $self->error; }
    else {
        if ( $som->dataof("//deleteResponse/writeResponse/status")
            ->attr->{'isSuccess'} eq 'true' )
        {
            return $som->dataof("//deleteResponse/writeResponse/baseRef")
              ->attr->{'internalId'};
        }
        else { $self->error; }
    }
}

sub _passport {
    my $self = shift;

    return SOAP::Header->name(
        'passport' => \SOAP::Data->value(
            SOAP::Data->name( 'email'    => $self->nsemail ),
            SOAP::Data->name( 'password' => $self->nspassword ),
            SOAP::Data->name( 'account'  => $self->nsaccount ),
            SOAP::Data->name('role')->attr( { 'internalId' => $self->nsrole } )
        ),
    );
}

sub map_sso {
    my ( $self, $args ) = @_;
    #$DB::single = 1;
    my $email    = $args->{email}    || die 'no email passed';
    my $password = $args->{password} || die 'no password passed';
    my $user_id  = $args->{user_id}  || die 'no user_id passed';
    my $role_id  = $args->{role_id}  || die 'no role_id passed';

    $self->soap->on_action( sub { return 'mapSso'; } );
    my $som = $self->soap->mapSso(
        $self->_passport,
        SOAP::Data->name(
            'ssoCredentials' => \SOAP::Data->value(
                SOAP::Data->name( 'email'    => $email ),
                SOAP::Data->name( 'password' => $password ),
                SOAP::Data->name( 'account'  => $self->nsaccount ),
                SOAP::Data->name(
                    authenticationToken =>
                      $self->_generate_auth_token($user_id),
                ),
                SOAP::Data->name( 'partnerId' => $self->nsaccount ),
                SOAP::Data->name('role')->attr( { 'internalId' => $role_id } )

            ),
        ),
    );

    if ( $som->fault ) {
        die "could not map_sso for user $user_id - " . $som->fault;

    }
    else {
        if ( $som->dataof("//mapSsoResponse/sessionResponse/status")
            ->attr->{'isSuccess'} eq 'true' )
        {
            return 1;
        }
        else {
            die "could not map_sso for user $user_id, role $role_id";
        }
    }

}

sub sso_url {
    my ( $self, $args ) = @_;
    my $user_id         = $args->{user_id} || die 'no user_id';
    my $return_url      = $args->{return_url};
    my $landing_url     = $args->{landing_url};
    my $hide_login_page = $args->{hide_login_page};

    die "custom domain unsupported, Netsuite sandbox does not work with it"
      if $args->{d};

    my %args = (
        a   => $self->_generate_auth_token($user_id),
        pid => $self->nsaccount,
        c   => $self->nsaccount,
        n   => $self->site_id,
    );

    $args{returnurl}     = $return_url      if $return_url;
    $args{landingurl}    = $landing_url     if $landing_url;
    $args{hideloginpage} = $hide_login_page if $hide_login_page;

    my $url = URI->new( $self->sso_href );

    $url->query_form( \%args );

    return $url->as_string;
}

sub cart_url {
    my ( $self, $args ) = @_;

    my $buy_id    = $args->{buy_id} || die 'no buy_id';
    my $show_cart = $args->{show_cart};
    my $quantity  = $args->{quantity} || 1;
    my $c         = $args->{c} || die 'no company id';

    my %args = (
        buyid => $buy_id,
        qty   => $quantity,
        c     => $c,
    );

    $args{showcart} = $show_cart if $show_cart;

    my $url = URI->new( $self->cart_href );

    $url->query_form( \%args );

    return $url->as_string;
}

sub _generate_auth_token {
    my ( $self, $user_id ) = @_;

    #$DB::single = 1;
    my $rsa_priv =
      Crypt::OpenSSL::RSA->new_private_key( $self->rsa_private_key );
    $rsa_priv->use_pkcs1_padding;

    # number of milliseconds since the epoch
    my $super_epoch = time() * 1000;

    my $authentication_token = $rsa_priv->private_encrypt(
        Encode::encode(
            'UTF8', join( ' ', $self->company, $user_id, $super_epoch )
        )
    );

    # convert encrypted token to hex
    my $token = uc( unpack( 'H*', $authentication_token ) );

    return $token;
}

sub add {
    my ( $self, $recordType, $recordRef ) = @_;

    $self->error("Invalid recordType: $recordType!")
      if !defined $self->record_namespaces->{$recordType};

    $self->soap->on_action( sub { return 'add'; } );
    my $som = $self->soap->add(
        $self->_passport,
        SOAP::Data->name(
            'record' => \SOAP::Data->value(
                $self->_parseRequest( ucfirst($recordType), $recordRef )
            )
          )->attr(
            {
                'xsi:type' => $self->record_namespaces->{$recordType} . ':'
                  . ucfirst($recordType)
            }
          )
    );

    if ( $som->fault ) { $self->error; }
    else {
        if ( $som->dataof("//addResponse/writeResponse/status")
            ->attr->{'isSuccess'} eq 'true' )
        {
            return $som->dataof("//addResponse/writeResponse/baseRef")
              ->attr->{'internalId'};
        }
        else {

            my $status_code = $som->dataof(
                "//addResponse/writeResponse/status/statusDetail/code")->value;
            if ($status_code) {
                die $status_code;
            }
            else {
                die "unknown error";
            }
        }
    }
}

sub update {
    my ( $self, $recordType, $recordRef ) = @_;

    my $internalId = $recordRef->{internalId};
    delete $recordRef->{internalId};

    $self->error("Invalid recordType: $recordType!")
      if !defined $self->record_namespaces->{$recordType};

    $self->soap->on_action( sub { return 'update'; } );
    my $som = $self->soap->update(
        $self->_passport,
        SOAP::Data->name(
            'record' => \SOAP::Data->value(
                $self->_parseRequest( ucfirst($recordType), $recordRef )
            )
          )->attr(
            {
                'xsi:type' => $self->record_namespaces->{$recordType} . ':'
                  . ucfirst($recordType),
                'internalId' => $internalId
            }
          )
    );

    if ( $som->fault ) { $self->error; }
    else {
        if ( $som->match("//updateResponse/writeResponse/status") ) {
            if ( $som->dataof("//updateResponse/writeResponse/status")
                ->attr->{'isSuccess'} eq 'true' )
            {
                return $som->dataof("//updateResponse/writeResponse/baseRef")
                  ->attr->{'internalId'};
            }
            else { $self->error; }
        }
        else { $self->error; }
    }

}

sub error {
    my $self = shift;

    my ($method) = ( ( caller(1) )[3] =~ /^.*::(.*)$/ );

    $self->{LAST_REQ} = $self->soap->transport->http_request->content();
    $self->{LAST_RES} = $self->soap->transport->http_response->content();

    # if an error is sent from the login method, it means someone is trying to
    # login, and we should handle the error differently.  If it is a customer
    # we want to know WHY they had an error.
    $self->{ERROR_RESULTS} = $self->_parseResponse;

    $self->_logTransport( $self->{ERRORDIR}, $method )
      if $self->{ERRORDIR};
    return;

}

sub errorResults {
    my ($self) = shift;
    if ( defined $self->{ERROR_RESULTS} ) {
        return $self->{ERROR_RESULTS};
    }
    else { return; }
}

sub _parseRequest {
    my ( $self, $requestType, $requestRef ) = @_;

    my @requestSoap;
    while ( my ( $key, $value ) = each %{$requestRef} ) {

        if ( ref $value eq 'ARRAY' ) {

            my $listElementName = $key;
            $listElementName =~ s/^(.*)List$/$1/;

            my @listElements;
            for my $listElement ( @{ $requestRef->{$key} } ) {

                my @sequence;

                # if the listElement is customField
                # handle it differently
                if ( $listElementName eq 'customField' ) {

                    my $element;

                    $element->{name} = 'customField';

                    $element->{attr}->{internalId} =
                      $listElement->{internalId};

                    $element->{attr}->{'xsi:type'} =
                      $listElement->{type};

                    $element->{value} = \SOAP::Data->name('value')
                      ->value( $listElement->{value} );
                    push @listElements, SOAP::Data->new( %{$element} );
                }
                else {

                    while ( my ( $key, $value ) = each %{$listElement} ) {
                        push @sequence,
                          $self->_parseRequestField(
                            ucfirst $requestType . ucfirst $listElementName,
                            $key, $value );
                    }
                    push @listElements,
                      SOAP::Data->name(
                        $listElementName => \SOAP::Data->value(@sequence) );
                }

            }

            if ( grep $_ eq $key, qw(addressbookList creditCardsList) ) {
                push @requestSoap,
                  SOAP::Data->name( $key => \SOAP::Data->value(@listElements) )
                  ->attr( { replaceAll => 'false' } );
            }
            else {
                push @requestSoap,
                  SOAP::Data->name( $key => \SOAP::Data->value(@listElements) );
            }

        }
        else {
            push @requestSoap,
              $self->_parseRequestField( $requestType, $key, $value );
        }
    }

    return @requestSoap;
}

sub _parseRequestField {
    my ( $self, $type, $key, $value ) = @_;

    my $element;
    if ( $self->record_fields->{$type}->{$key} eq 'core:RecordRef' ) {
        $element->{attr}->{internalId} = $value;
    }
    else { $element->{value} = $value; }
    $element->{name} = $key;

    $element->{attr}->{'xsi:type'} =
      $self->record_fields->{$type}->{$key};

    return SOAP::Data->new( %{$element} );

}

sub _logTransport {
    my $self   = shift;
    my $path   = shift;
    my $method = shift;

    my $dir = "$path/$method";
    if ( !-d $dir ) {
        mkdir $dir, 0777 or croak "Unable to create directory $dir";
    }

    my $fileName    = time;
    my $xmlRequest  = "$fileName-req.xml";
    my $xmlResponse = "$fileName-res.xml";

    my $flag;
    my $fh = File::Util->new();
    $flag = $fh->write_file(
        'file'    => "$dir/$xmlRequest",
        'content' => $self->{LAST_REQ},
        'bitmask' => 0644
    );

    if ( !$flag ) { croak "Unable to create file $dir/$xmlRequest" }

    $flag = $fh->write_file(
        'file'    => "$dir/$xmlResponse",
        'content' => $self->{LAST_RES},
        'bitmask' => 0644
    );

    if ( !$flag ) { croak "Unable to create file $dir/$xmlResponse" }

}

sub _parseResponse {
    my ($self) = shift;

    # determine the method of the caller (login, get, search, etc)
    my ($method) = ( ( caller(1) )[3] =~ /^.*::(.*)$/ );

    $self->{LAST_REQ} = $self->soap->transport->http_request->content();
    $self->{LAST_RES} = $self->soap->transport->http_response->content();

    my $p = new XML::Parser( Style => 'EasyTree' );
    my $tree = $p->parse( $self->{LAST_RES} );

    use vars qw($body $head);
    for my $header ( @{ $tree->[0]->{content} } ) {
        if    ( $header->{name} =~ /^.*:Header$/ ) { $head = $header; }
        elsif ( $header->{name} =~ /^.*:Body$/ )   { $body = $header; }
    }

    $self->time(time);
    $self->{LAST_HEAD} = $head;
    $self->{LAST_BODY} = $body;

    if ( $method eq 'error' ) {

        # if the error is NOT being produced by the login function, the
        # structure is different, so the parsing must be different
        if (
            ref $body->{content}->[0]->{content}->[0]->{content}->[0]->{content}
            eq 'ARRAY' )
        {
            return &_parseFamily(
                $body->{content}->[0]->{content}->[0]->{content}->[0]->{content}
            );
        }
        elsif ( $body->{content}->[0]->{content}->[2]->{content}->[0]->{content}
            ->[0]->{name} =~ m/ns1:code/ )
        {
            return &_parseFamily(
                $body->{content}->[0]->{content}->[2]->{content}->[0]->{content}
            );
        }
        elsif (
            $body->{content}->[0]->{content}->[2]->{content}->[0]->{name} eq
            'ns1:hostname' )
        {
            return &_parseFamily( $body->{content}->[0]->{content} );
        }
        else {
            croak 'Unable to parse error response!  Contact module author..';
        }
    }
    elsif ( ref $body->{content}->[0]->{content}->[0]->{content} eq 'ARRAY' ) {
        return &_parseFamily(
            $body->{content}->[0]->{content}->[0]->{content} );
    }
    else { return; }

}

sub _parseFamily {
    my ( $array_ref, $store_ref ) = @_;

    my $parse_ref;
    for my $node ( @{$array_ref} ) {

        $node->{name} =~ s/^(.*:)?(.*)$/$2/g;
        if ( !defined $node->{content}->[0] ) {
            $parse_ref = &_parseNode( $node, $parse_ref );
        }
        else {
            if ( scalar @{ $node->{content} } == 1 ) {
                if ( ref $node->{content}->[0]->{content} eq 'ARRAY' ) {
                    if ( scalar @{ $node->{content}->[0]->{content} } > 1 ) {

 #$parse_ref->{$node->{name}} = &_parseFamily($node->{content}->[0]->{content});
                        push @{ $parse_ref->{ $node->{name} } },
                          &_parseFamily( $node->{content} );
                    }
                    else {

                        if ( $node->{name} =~ /List$/ ) {
                            if (
                                scalar @{ $node->{content}->[0]->{content} } >
                                1 )
                            {
                                for ( 0 .. scalar @{ $node->{content} } - 1 ) {
                                    push @{ $parse_ref->{ $node->{name} } },
                                      &_parseFamily(
                                        $node->{content}->[0]->{content} );
                                }
                            }
                            else {
                                if ( !ref $node->{content}->[0]->{content}->[0]
                                    ->{content} )
                                {
                                    $parse_ref =
                                      &_parseNode( $node->{content}->[0],
                                        $parse_ref );
                                }
                                else {
                                    push @{ $parse_ref->{ $node->{name} } },
                                      &_parseNode(
                                        $node->{content}->[0]->{content}->[0] );
                                }
                            }
                        }
                        else {
                            $parse_ref = &_parseNode( $node, $parse_ref );
                        }

                    }
                }
                else { $parse_ref = &_parseNode( $node, $parse_ref ); }
            }
            else {

                if ( $node->{name} =~ /(List|Matrix)$/ ) {
                    if ( scalar @{ $node->{content}->[0]->{content} } > 1 ) {
                        for ( 0 .. scalar @{ $node->{content} } - 1 ) {
                            my $record =
                              &_parseFamily(
                                $node->{content}->[$_]->{content} );
                            $record =
                              &_parseAttributes( $node->{content}->[$_],
                                $record );
                            push @{ $parse_ref->{ $node->{name} } }, $record;
                        }
                    }
                    else {
                        for ( 0 .. scalar @{ $node->{content} } - 1 ) {
                            if ( !ref $node->{content}->[$_]->{content}->[0]
                                ->{content} )
                            {
                                $parse_ref =
                                  &_parseNode( $node->{content}->[$_],
                                    $parse_ref );
                            }
                            else {
#if ($node->{name} eq 'customFieldList') {
#    push @{ $parse_ref->{$node->{name}} }, &_parseNode($node->{content}->[$_]);
#}
                                if ( !ref $node->{content}->[$_]->{content}->[0]
                                    ->{content}->[0]->{content} )
                                {
                                    push @{ $parse_ref->{ $node->{name} } },
                                      &_parseNode( $node->{content}->[$_] );
                                }
                                elsif (
                                    ref $node->{content}->[$_]->{content}->[0]
                                    ->{content}->[0]->{content} )
                                {
                                    push @{ $parse_ref->{ $node->{name} } },
                                      &_parseNode(
                                        $node->{content}->[$_]->{content}->[0]
                                      );
                                }
                                else {
                                    push @{ $parse_ref->{ $node->{name} } },
                                      &_parseNode( $node->{content}->[$_] );
                                }
                            }
                        }
                    }
                }
                else {
                    $parse_ref = &_parseFamily( $node->{content}, $parse_ref );
                }
            }
        }
        $parse_ref = &_parseAttributes( $node, $parse_ref );
    }

    if ($store_ref) {
        while ( my ( $key, $val ) = each %{$parse_ref} ) {
            $store_ref->{$key} = $val;
        }
        return $store_ref;
    }
    else { return $parse_ref; }

}

sub _parseAttributes {
    my ( $hash_ref, $store_ref ) = @_;

    my $parse_ref;
    if ( defined $hash_ref->{name} ) {
        $hash_ref->{name} =~ s/^(.*:)?(.*)$/$2/g;
    }

    if ( defined $hash_ref->{attrib} ) {
        for my $attrib ( keys %{ $hash_ref->{attrib} } ) {
            next if $attrib =~ /^xmlns:/;
            if ( $attrib =~ /^xsi:type$/ ) {
                $hash_ref->{attrib}->{$attrib} =~ s/^(.*:)?(.*)$/lcfirst($2)/eg;
                $parse_ref->{ $hash_ref->{name} . 'Type' } =
                  $hash_ref->{attrib}->{$attrib};
            }
            else {
                $parse_ref->{ $hash_ref->{name} . ucfirst($attrib) } =
                  $hash_ref->{attrib}->{$attrib};
            }
        }
    }

    if ($store_ref) {
        while ( my ( $key, $val ) = each %{$parse_ref} ) {
            $store_ref->{$key} = $val;
        }
        return $store_ref;
    }
    else { return $parse_ref; }

}

sub _parseNode {
    my ( $hash_ref, $store_ref ) = @_;

    my $parse_ref;
    if ( defined $hash_ref->{name} ) {
        $hash_ref->{name} =~ s/^(.*:)?(.*)$/$2/g;
    }

    if ( scalar @{ $hash_ref->{content} } == 1 ) {

 # if the name of the inner attribute is "name", then only worry about the value
        if ( defined $hash_ref->{content}->[0]->{name} ) {
            $hash_ref->{content}->[0]->{name} =~ /^(.*:)?(name|value)$/;
            if ( defined $hash_ref->{content}->[0]->{attrib}->{internalId} ) {
                $parse_ref->{ $hash_ref->{name} . ucfirst($2) } =
                  $hash_ref->{content}->[0]->{attrib}->{internalId};
            }
            else {
                $parse_ref->{ $hash_ref->{name} . ucfirst($2) } =
                  $hash_ref->{content}->[0]->{content}->[0]->{content};
            }
        }
        else {
            if ( defined $hash_ref->{content}->[0]->{content} ) {
                if ( !ref $hash_ref->{content}->[0]->{content} ) {
                    $parse_ref->{ $hash_ref->{name} } =
                      $hash_ref->{content}->[0]->{content};
                }
            }
        }
    }

    $parse_ref = &_parseAttributes( $hash_ref, $parse_ref );

    if ( ref $store_ref eq 'HASH' ) {
        while ( my ( $key, $val ) = each %{$parse_ref} ) {
            $store_ref->{$key} = $val;
        }
        return $store_ref;
    }
    else { return $parse_ref; }

}

1;

__END__

=head1 NAME

WebService::NetSuite - A perl  interface to the NetSuite SuiteTalk (Web Services) API

=head1 SYNOPSIS

    use WebService::NetSuite;
  
    my $ns = WebService::NetSuite->new({
        nsrole     => 3,
        nsemail    => 'blarg@foo.com',
        nspassword => 'foobar123',
        nsaccount  => 123456,
        sandbox    => 1,
    });

    my $customer_id = $ns->add( 'customer',
        { firstName  => 'Gonzo',
          lastName   => 'Muppet',
          email      => 'gonzo@muppets.com',
          entityId   => 'muppet_database_id',
          subsidiary => 1,
          isPerson   => 1,
    });

=head1 DESCRIPTION

This module is a client to the NetSuite SuiteTalk web service API.

Initial content shamelessly stolen from https://github.com/gitpan/NetSuite

Refactored and released as WebService::NetSuite for the 2013 target and
updated access methods using the passport data structure instead of login/logout.

This reboot of the original NetSuite module is still rough and under construction.

NetSuite Help Center - https://system.sandbox.netsuite.com/app/help/helpcenter.nl

You'll need a NetSuite login to get to the help center unfortunately. Silly NetSuite.

=head2 add(recordType, hashReference)

The add method submits a new record to NetSuite.  It requires a record type,
and hash reference containing the data of the record.

For a boolean value, the request uses a numeric zero to represent false, and
the textual word "true" to represent true.  I believe this is an error with
NetSuite; identified in their last release.

For a record reference field, like entityStatus, simply pass the numeric
internalId of the field.  If you are unsure what the internalIds are for
a value, check the getSelectValue method.

For an enumerated value, simply submit a string.

For a list value, pass an array of hashes.

    my $customer = {
        isPerson => 0, # meaning false
        companyName => 'Wolfe Electronics',
        entityStatus => 13, # notice I only pass in the internalId
        emailPreference => '_hTML', # enumerated value
        unsubscribe => 0,
        addressbookList => [
          {
              defaultShipping => 'true',
              defaultBilling => 0,
              isResidential => 0,
              phone => '650-627-1000',
              label => 'United States Office',
              addr1 => '2955 Campus Drive',
              addr2 => 'Suite 100',
              city => 'San Mateo',
              state => 'CA',
              zip => '94403',
              country => '_unitedStates',
          },
        ],
    };

    my $internalId = $ns->add('customer', $customer);
    print "I have added a customer with internalId $internalId\n";

If successful this method will return the internalId of the newly generated
record.  Otherwise, the error details are sent to the errorResults method.

If you wanted to ensure a record was submitted successfully, I recommend
the following syntax:

    if (my $internalId = $ns->add('customer', $customer)) {
        print "I have added a customer with internalId $internalId\n";
    }
    else {
        print "I failed to add the customer!\n";
    }

=head2 update(recordType, hashReference)

The update method will request an update of an existing record.  The only
difference with this operation is that the internalId of the record being
updated must be present inside the hash reference.

    my $customer = {
        internalId => 1234, # the internaldId of the record being updated
        phone => '555-555-5555',
    };

    my $internalId = $ns->update('customer', $customer);
    print "I have updated a customer with internalId $internalId\n";
    
If successful this method will return the internalId of the updated record
Otherwise, the error details are sent to the errorResults method.

=head2 delete(recordType, internalId)

The delete method very simply deletes a record.  It requires the record type
and internalId number for the record.

    my $internalId = $ns->delete('customer', 1234);
    print "I have deleted a customer with internalId $internalId\n";

If successful this method will return the internalId of the deleted record
Otherwise, the error details are sent to the errorResults method.

=head2 search(searchType, hashReference, configReference)

The search method submits a query to NetSuite.  If the
query is successful, a true value (1) is returned, otherwise it is
undefined.

To conduct a very basic search for all customers, excluding inactive accounts,
I would write:

    my $query = {
        basic => [
            { name => 'isInactive', value => 0 } # 0 means false
        ]
    };
    
    $ns->search('customer', $query);
    
Notice that the query is a hash reference of search types.  Foreach search type
in the hash there is an array of hashes for each field in the criteria.

Once the query is constructed, I designate the search to use and the query.
And submit it to NetSuite.

This query structure may seem confusing, especially in a simply example.  But
within NetSuite there are several different searches you can perform.
Some examples of these searchs are:

customer
contact
supportCase
employee
calendarEvent
item
opportunity
phoneCall
task
transaction

Then within each search, you can also B<join> with other searches to combine
information.  To demonstrate a more complex search, we will take this example.

Let's imagine you wanted to see transactions, specifically sales orders,
invoices, and cash sales, that have transpired over the last year.

    my $query = {
        basic => [
            { name => 'mainline', value => 'true' },
            { name => 'type', attr => { operator => 'anyOf' }, value => [
                    { value => '_salesOrder' },
                    { value => '_invoice' },
                    { value => '_cashSale' },
                ]   
            },
            { name => 'tranDate', value => 'previousOneYear', attr => { operator => 'onOrAfter' } },
        ],
    };
    
From that list, you want to see if the customer associated with each transaction
has a valid email address on file, and is not a lead or a prospect.  The
joined query would look like this:

    my $query = {
        basic => [
            { name => 'mainline', value => 'true' },
            { name => 'type', attr => { operator => 'anyOf' }, value => [
                    { value => '_salesOrder' },
                    { value => '_invoice' },
                    { value => '_cashSale' },
                ]   
            },
            { name => 'tranDate', value => 'previousOneYear', attr => { operator => 'onOrAfter' } },
        ],
        customerJoin => [
            { name => 'email', attr => { operator => 'notEmpty' } },
            { name => 'entityStatus', attr => { operator => 'anyOf' }, value => [
                    { attr => { internalId => '13' } },
                    { attr => { internalId => '15' } },
                    { attr => { internalId => '16' } },
                ]                                  
            },
        ],
    };
    
Notice that each hash reference within either the basic or customerJoin
arrays has a "name" and "value" key.  In some cases you also have an
"attr" key.  This "attr" key is another hash reference that contains
the operator for a field, or the internalId for a field.

Also notice that for enumerated search fields, like "entityStatus" or "type",
the "value" key contains an array of hashes.  Each of these hashes represent
one of many possible collections.

To take this a step further, we may want to search for some custom fields
that exists in a customer's record.  These custom fields are located in the
"customFieldList" field of a record and can be queries like so:

    my $query = {
        basic => [
            { name => 'customFieldList', value => [
                    {
                        name => 'customField',
                        attr => {
                            internalId => 'custentity1',
                            operator => 'anyOf',
                            'xsi:type' => 'core:SearchMultiSelectCustomField'
                        },
                        value => [
                            { attr => { internalId => 1 } },
                            { attr => { internalId => 2 } },
                            { attr => { internalId => 3 } },
                            { attr => { internalId => 4 } },
                        ]
                    },
                ],
            },
        ],
    };
    
Notice that we have added a new layer to the "attr" key called 'xsi:type'.
That is because this module cannot determine the custom field types for YOUR
particular NetSuite account in real time.  Thus, you have to provide them
within the query.

If the search is successful, a true value (1) is returned, otherwise it is
undefined.  If successful, the results are passed to the searchResults method,
otherwise call the errorResults method.

Also, for this method, you are given special access to the header of the
search request.  This allows you to designate the number of records to be
returned in each set, as well as whether to return just basic information
about the results, or extended information about the results.

    # perform a search and only return 10 records per page
    $ns->search('customer', $query, { pageSize => 10 });
    
    # perform a search and only provide basic information about the results
    $ns->search('customer', $query, { bodyFieldsOnly => 0 });

=head2 searchResults

The searchResults method returns the results of a successful search request.
It is a hash reference that contains the record list and details of the search.

    {
        'recordList' => [
            {
                'accessRoleName' => 'Customer Center',
                'priceLevelInternalId' => '3',
                'unbilledOrders' => '2512.7',
                'entityStatusName' => 'CUSTOMER-Closed Won',
                'taxItemInternalId' => '-112',
                'lastPageVisited' => 'login-register',
                'isInactive' => 'false',
                'shippingItemName' => 'UPS Ground',
                'entityId' => 'A Wolfe',
                'entityStatusInternalId' => '13',
                'accessRoleInternalId' => '14',
                'recordExternalId' => 'entity-5',
                'webLead' => 'No',
                'territoryName' => 'Default Round-Robin',
                'recordType' => 'customer',
                'emailPreference' => '_default',
                'taxItemName' => 'CA-SAN MATEO',
                'taxable' => 'true',
                'partnerName' => 'E Auctions Online',
                'companyName' => 'Wolfe Electronics',
                'shippingItemInternalId' => '92',
                'leadSourceName' => 'Accessory Sale',
                'creditHoldOverride' => '_auto',
                'title' => 'Perl Developer',
                'priceLevelName' => 'Employee Price',
                'partnerInternalId' => '170',
                'giveAccess' => 'true',
                'visits' => '150',
                'stage' => '_customer',
                'termsName' => 'Due on receipt',
                'defaultAddress' => 'A Wolfe<br>2955 Campus Drive<br>Suite 100
<br>San Mateo CA 94403<br>United States',
                'lastVisit' => '2008-03-22T16:40:00.000-07:00',
                'isPerson' => 'false',
                'recordInternalId' => '-5',
                'fax' => '650-627-1001',
                'salesRepInternalId' => '23',
                'dateCreated' => '2006-07-22T00:00:00.000-07:00',
                'termsInternalId' => '4',
                'salesRepName' => 'Clark Koozer',
                'unsubscribe' => 'false',
                'categoryInternalId' => '2',
                'phone' => '650-555-9788',
                'shipComplete' => 'false',
                'lastModifiedDate' => '2008-01-28T19:28:00.000-08:00',
                'territoryInternalId' => '-5',
                'categoryName' => 'Individual',
                'firstVisit' => '2007-03-24T16:13:00.000-07:00',
                'leadSourceInternalId' => '100102'
            },
        ],
        'totalPages' => '79', # the total number of pages in the set
        'totalRecords' => '790', # the total records returned by the search
        'pageSize' => '10', # the number of records per page
        'pageIndex' => '1', # the current page
        'statusIsSuccess' => 'true'
    }
    
The "recordList" field is an array of hashes containing a record's values.
Refer to the get method for details on the understanding of a record's data
structure.

=head2 searchMore(pageIndex)

If your initial search returns several pages of results, you can jump
to another result page quickly using the searchMore method.

For example, if after performing an initial search you are given 1 of 100
records, when there are 500 total records.  You could quickly jump to the
301-400 block of records by entering the pageIndex value.

    $ns->search('customer', $query);
    
    # determine my result set
    my $totalPages = $ns->searchResults->{totalPages};
    my $pageIndex = $ns->searchResults->{pageIndex};
    my $totalRecords = $ns->searchResults->{totalRecords};
    
    # output a message
    print "I found $totalRecords records!\n";
    print "Displaying page $pageIndex of $totalPages\n";
    
    my $jumpToPage = 3;
    $ns->searchMore($jumpToPage);
    print "Jumping to page $jumpToPage\n";
    print "Now displaying page $jumpToPage of $totalPages\n";

=head2 searchNext

If your initial search returns several pages of results, you can automatically
jump to the next page of results using the searchNext function.  This is
most useful when downloading sets of more than 1000 records.  (Which is the
limit of an initial search).

    $ns->search('transaction', $query);
    if ($ns->searchResults->{totalPages} > 1) {
        while ($ns->searchResults->{pageIndex} != $ns->searchResults->{totalPages}) {
            for my $record (@{ $ns->searchResults->{recordList} }) {
                my $internalId = $record->{recordInternalId};
                print "Found record with internalId $internalId\n";
            }
            $ns->searchNext;
        }
    }

=head2 get(recordType, internalId)

The get method returns the most complete information for a record.

    # to see an individual field in the response
    if ($ns->get('customer', 1234)) {
        my $firstName = $ns->getResults->{firstName};
        print "I got a customer with the first name $firstName\n";
    }
    
    # to output the complete data structure
    my $getSuccess = $ns->get('customer', 1234);
    if ($getSuccess) {
        print Dumper($ns->getResults);
    }
    
If the operation in successful, a true value (1) is returned,
otherwise it is undefined.

The results will be passed to the getResults method, otherwise
call the errorResults method.

=head2 getResults

The getResults method returns a hash reference containing all of the
information for a given record.  (Some fields were omitted)

    {
        'recordInternalId' => '1234',
        'recordExternalId' => 'entity-5',
        'recordType' => 'customer',
        'isInactive' => 'false',
        'entityStatusInternalId' => '13',
        'entityStatusName' => 'CUSTOMER-Closed Won',
        'entityId' => 'A Wolfe',
        'emailPreference' => '_default',
        'fax' => '650-627-1001',
        'contactList' => [
            {
                'contactInternalId' => '25',
                'contactName' => 'Amy Nguyen'
            },
        ],
        'creditCardsList' => [
            {
                'ccDefault' => 'true',
                'ccMemo' => 'This is the preferred credit card.',
                'paymentMethodName' => 'Visa',
                'paymentMethodInternalId' => '5',
                'ccNumber' => '************1111',
                'ccExpireDate' => '2010-01-01T00:00:00.000-08:00',
                'ccName' => 'A Wolfe'
            }
        ],
        'addressbookList' => [
            {
                'country' => '_unitedStates',
                'defaultShipping' => 'true',
                'internalId' => '244715',
                'defaultBilling' => 'true',
                'phone' => '650-627-1000',
                'state' => 'CA',
                'addrText' => 'A Wolfe<br>2955 Campus Drive<br>Suite 100<br>San Mateo CA 94403<br>United States',
                'addr2' => 'Suite 100',
                'zip' => '94403',
                'city' => 'San Mateo',
                'isResidential' => 'false',
                'addressee' => 'A Wolfe',
                'addr1' => '2955 Campus Drive',
                'override' => 'false',
                'label' => 'Default'
            }
        ],
        'dateCreated' => '2006-07-22T00:00:00.000-07:00',
        'lastModifiedDate' => '2008-01-28T19:28:00.000-08:00',
    };
    
It is important to note how some of this data is returned.

Notice that the internalId for the record is labeled "recordInternalId"
instead of just "internalId".  This is the same for the "recordExternalId".

For a boolean value, the response the string "true" or "false.

For a record reference field, like entityStatus, the name of this value
and its internalId are returned as two seperate values: entityStatusName
and entityStatusInternalId.  This appending of the words "Name" and "InternalId"
after the field name is the same for all reference fields.

For an enumerated value, a string is returned.

For a list, the value is an array of hashes.  Even if the list contains only
a single hash reference, it will still be returned as an array.

The easiest way to access an understand this function, is to dump the response
and determine the best way to interate through your data.  For example,
if I wanted to see if the customer had a default credit card selected, I might
write:

    if ($ns->get('customer', 1234)) {
        if (defined $ns->getResults->{creditCardsList}) {
            if (scalar @{ $ns->getResults->{creditCardsList} } == 1) {
                print "This customer has a default credit card!\n";
            }
            else { 
                for my $creditCard (@{ $ns->getResults->{creditCardsList} }) {
                    if ($creditCard->{ccDefault} eq 'true') {
                        print "This customer has a default credit card!\n";
                    }
                }
            }
        }
        else {
            "There are no credit cards on file!\n";
        }
    }
    else {
        # my get request failed, better check the errorResults method
    }
    
Or, if I was more concerned with checking this customers last activity, I
might write:

    $ns->get('customer', 1234);
    
    # assuming the request was successful
    my $internalId = $ns->getResults->{recordInternalId};
    my $lastModifiedDate = $ns->getResults->{lastModifiedDate};
    print "Customer $internalId was last updated on $lastModifiedDate.\n";

=head2 getSelectValue

The getSelectValue method returns a list of internalId numbers and names for
a record reference field.  For instance, if you wanted to know all of the
acceptable values for the "terms" field of a customer you could submit
a request like:

    $ns->getSelectValue('customer_terms');
    
If successful, a call to the getResults method, will return a hash reference
that looks like this:

    {
        'recordRefList' => [
          {
              'recordRefInternalId' => '5',
              'recordRefName' => '1% 10 Net 30'
          },
          {
              'recordRefInternalId' => '6',
              'recordRefName' => '2% 10 Net 30'
          },
          {
              'recordRefInternalId' => '4',
              'recordRefName' => 'Due on receipt'
          },
          {
              'recordRefInternalId' => '1',
              'recordRefName' => 'Net 15'
          },
          {
              'recordRefInternalId' => '2',
              'recordRefName' => 'Net 30'
          },
          {
              'recordRefInternalId' => '3',
              'recordRefName' => 'Net 60'
          }
        ],
        'totalRecords' => '6',
        'statusIsSuccess' => 'true'
    }
    
If the request fails, the error details are sent to the errorResults method.

From these results, we now know that the "terms" field of a customer can be
submitted using any of the recordRefInternalIds.  Thus, to update a customer's
terms, we might write:

    my $customer = {
        internalId => 1234,
        terms => 4, # Due on receipt
    }

    $ns->update('customer', $customer);

For a complete list of acceptable values for this operation, visit the
coreTypes XSD file for web services version 2.6.
Look for the "GetSelectValueType" simpleType.

L<https://webservices.netsuite.com/xsd/platform/v2_6_0/coreTypes.xsd>

=head2 getCustomization

The getCustomization retrieves the metadata for Custom Fields, Lists, and
Record Types.  For instance, if you wanted to know all of the
custom fields for the body of a transaction, you might write:

    $ns->getCustomization('transactionBodyCustomField');
    
If successful, a call to the getResults method, will return a hash reference
that looks like this:

    {
        'recordList' => [
          {
              'fieldType' => '_phoneNumber',
              'sourceFromName' => 'Phone',
              'bodyPrintStatement' => 'false',
              'bodyAssemblyBuild' => 'false',
              'bodySale' => 'true',
              'bodyItemReceiptOrder' => 'false',
              'isMandatory' => 'false',
              'recordType' => 'transactionBodyCustomField',
              'bodyPurchase' => 'false',
              'bodyPickingTicket' => 'true',
              'bodyExpenseReport' => 'false',
              'name' => 'Entity',
              'bodyItemFulfillmentOrder' => 'false',
              'bodyPrintPackingSlip' => 'false',
              'isFormula' => 'false',
              'sourceFromInternalId' => 'STDENTITYPHONE',
              'bodyItemFulfillment' => 'false',
              'label' => 'Customer Phone',
              'bodyJournal' => 'false',
              'showInList' => 'false',
              'recordInternalId' => 'CUSTBODY1',
              'help' => 'This is the customer\'s phone number from the
customer record.  It is generated dynamically every time the form is accessed
 - so that changes in the customer record will be reflected the next time the
 transaction is viewed/edited/printed.<br>Note: This is an example of a
 transaction body field, sourced from a customer standard field.',
              'storeValue' => 'false',
              'isParent' => 'false',
              'defaultChecked' => 'false',
              'bodyInventoryAdjustment' => 'false',
              'bodyOpportunity' => 'false',
              'bodyPrintFlag' => 'true',
              'checkSpelling' => 'false',
              'displayType' => '_disabled',
              'bodyItemReceipt' => 'false',
              'sourceListInternalId' => 'STDBODYENTITY',
              'bodyStore' => 'false'
          },
          'totalRecords' => '1',
          'statusIsSuccess' => 'true'
    };

If the request fails, the error details are sent to the errorResults method.

For a complete list of acceptable values for this operation, visit the
coreTypes XSD file for web services version 2.6.
Look for the "RecordType" simpleType.

L<https://webservices.netsuite.com/xsd/platform/v2_6_0/coreTypes.xsd>

=head2 errorResults

The errorResults method is populated when a request returns an erroneous
response from NetSuite.  These errors can occur at anytime and with any
operation.  B<Always assume your operations will fail, and build your
code accordingly.>

The hash reference that is returned looks like this:

    {
        'message' => 'You have entered an invalid email address or account
number. Please try again.',
        'code' => 'INVALID_LOGIN_CREDENTIALS'
    };

If there is something FUNDAMENTALLY wrong with your request
(like you have included an invalid field), your errorResults
may look like this:

    {
        'faultcode' => 'soapenv:Server.userException',
        'detailDetail' => 'partners-java002.svale.netledger.com',
        'faultstring' => 'com.netledger.common.schemabean.NLSchemaBeanException:
<<somefield>> not found on {urn:relationships_2_6.lists.webservices.netsuite.com}Customer'
    };
    
Thus, a typical error-prepared script might look like this:

    $ns->login or die "Can't connect to NetSuite!\n";
    
    if ($ns->search('customer', $query)) {
        for my $record (@{ $ns->searchResults->{recordList} }) {
            if ($ns->get('customer', $record->{recordInternalId})) {
                print Dumper($ns->getResults);
            }
            else {
                # If an error is encountered while running through
                # a list, print a notice and break the loop
                print "An error occured!\n";
                last;
            }
        }
    }
    else {
        
        # I really want to know why my search would fail
        # lets output the error and message
        my $message = $ns->errorResults->{message};
        my $code = $ns->errorResults->{code};
        
        print "Unable to perform search!\n";
        print "($code): $message\n";
        
    }
    
    $ns->logout; # no error handling here, if this fails, oh well.

For a complete listing of errors and associated messages, consult the
SuiteTalk (Web Services) Records Guide.

L<http://www.netsuite.com/portal/developers/resources/suitetalk-documentation.shtml>

=head1 AUTHOR

Fred Moyer, L<fred@redhotpenguin.com>

=head1 LICENCE AND COPYRIGHT

Copyright 2013, iParadigms LLC.

Original Netsuite module copyright (c) 2008, Jonathan Lloyd. All rights reserved.

This module is free software; you can redistribute it and/or
modify it under the same terms as Perl itself. See L<perlartistic>.

=head1 ACKNOWLEDGEMENTS

Initial content shamelessly stolen from https://github.com/gitpan/NetSuite

Thanks to iParadigms LLC for sponsoring the reboot of this module.

=cut