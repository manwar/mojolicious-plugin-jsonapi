package Mojolicious::Plugin::JSONAPI;

use Mojo::Base 'Mojolicious::Plugin';

use JSONAPI::Document;
use Carp                  ();
use Lingua::EN::Inflexion ();

# ABSTRACT: Mojolicious Plugin for building JSON API compliant applications.

sub register {
    my ( $self, $app, $args ) = @_;
    $args ||= {};

    # Detect application/vnd.api+json content type, fallback to application/json
    $app->types->type(
        json => [ 'application/vnd.api+json', 'application/json' ] );

    my $namespace = exists( $args->{namespace} ) ? $args->{namespace} : 'api';
    $self->create_route_helpers( $app, $namespace );
    $self->create_data_helpers($app);
    $self->create_error_helpers($app);
}

sub create_route_helpers {
    my ( $self, $app, $namespace ) = @_;

    $app->helper(
        resource_routes => sub {
            my ( $c, $spec ) = @_;
            $spec->{resource} || Carp::confess('resource is a required param');
            $spec->{relationships} ||= [];

            my $resource = Lingua::EN::Inflexion::noun( $spec->{resource} );
            my $resource_singular = $resource->singular;
            my $resource_plural   = $resource->plural;

            my $base_path  = $namespace ? "/$namespace/$resource_plural" : "/$resource_plural";
            my $controller = $spec->{controller} || "api-$resource_plural";

            my $r = $app->routes->under($base_path)->to( controller => $controller );
            $r->get('/')->to( action => "fetch_${resource_plural}" );
            $r->post('/')->to( action => "post_${resource_singular}" );
            foreach my $method (qw/get patch delete/) {
                $r->$method("/:${resource_singular}_id")->to( action => "${method}_${resource_singular}" );
            }

            foreach my $relationship ( @{ $spec->{relationships} } ) {
                my $path = "/:${resource_singular}_id/relationships/${relationship}";
                foreach my $method (qw/get post patch delete/) {
                    $r->$method($path)->to( action => "${method}_related_${relationship}" );
                }
            }
        }
    );
}

sub create_data_helpers {
    my ( $self, $app ) = @_;

    my $jsonapi = JSONAPI::Document->new();

    $app->helper(
        resource_document => sub {
            my ( $c, $row, $options ) = @_;
            return $jsonapi->resource_document( $row, $options );
        }
    );

    $app->helper(
        compound_resource_document => sub {
            my ( $c, $row, $options ) = @_;
            return $jsonapi->compound_resource_document( $row, $options );
        }
    );

    $app->helper(
        resource_documents => sub {
            my ( $c, $resultset, $options ) = @_;
            return $jsonapi->resource_documents( $resultset, $options );
        }
    );
}

sub create_error_helpers {
    my ( $self, $app ) = @_;

    $app->helper(
        render_error => sub {
            my ( $c, $status, $errors, $data, $meta ) = @_;

            unless ( defined($errors) && ref($errors) ne 'ARRAY' ) {
                $errors = [
                    {
                        status => $status || 500,
                        title  => 'Error processing request',
                    }
                ];
            }

            return $c->render(
                status => $status || 500,
                json => {
                    $data ? $data : (),
                    $meta ? ( meta => $meta ) : (),
                    errors => $errors,
                }
            );
        }
    );
}

1;

__END__

=encoding UTF-8

=head1 NAME

Mojolicious::Plugin::JSONAPI - Mojolicious Plugin for building JSON API compliant applications

=head1 SYNOPSIS

    # Mojolicious

    # Using route helpers

    sub startup {
        my ($self) = @_;

        $self->plugin('JSONAPI', { namespace => 'api' });

        $self->resource_routes({
            resource => 'post',
            relationships => ['author', 'comments'],
        });

        # Now the following routes are available:

        # GET '/api/posts' -> to('api-posts#fetch_posts')
        # POST '/api/posts' -> to('api-posts#post_posts')
        # GET '/api/posts/:post_id -> to('api-posts#get_post')
        # PATCH '/api/posts/:post_id -> to('api-posts#patch_post')
        # DELETE '/api/posts/:post_id -> to('api-posts#delete_post')

        # GET '/api/posts/:post_id/relationships/author' -> to('api-posts#get_related_author')
        # POST '/api/posts/:post_id/relationships/author' -> to('api-posts#post_related_author')
        # PATCH '/api/posts/:post_id/relationships/author' -> to('api-posts#patch_related_author')
        # DELETE '/api/posts/:post_id/relationships/author' -> to('api-posts#delete_related_author')

        # GET '/api/posts/:post_id/relationships/comments' -> to('api-posts#get_related_comments')
        # POST '/api/posts/:post_id/relationships/comments' -> to('api-posts#post_related_comments')
        # PATCH '/api/posts/:post_id/relationships/comments' -> to('api-posts#patch_related_comments')
        # DELETE '/api/posts/:post_id/relationships/comments' -> to('api-posts#delete_related_comments')

        # You can use the following helpers too:

        $self->resource_document($dbic_row, $options);

        $self->compound_resource_document($dbic_row, $options);

        $self->resource_documents($dbic_resultset, $options);
    }

=head1 DESCRIPTION

This module intends to supply the user with helper methods that can be used to build a JSON API
compliant Mojolicious server. It helps create routes for your resources that conform with the
specification, along with supplying helper methods to use when responding to requests.

See L<http://jsonapi.org/> for the JSON API specification. At the time of writing, the version was 1.0.

=head1 OPTIONS

=over

=item C<namespace>

The prefix that's added to all routes, defaults to 'api'. You can also provided an empty string as the namespace,
meaing no prefix will be added.

=back

=head1 HELPERS

=head2 resource_routes(I<HashRef> $spec)

Creates a set of routes for the given resource. C<$spec> is a hash reference that can consist of the following:

    {
        resource        => 'post', # name of resource, required
        controller      => 'api-posts', # name of controller, defaults to "api-{resource_plural}"
        relationships   => ['author', 'comments'], # default is []
    }

C<resource> should be a singular noun, which will be turned into it's pluralised version (e.g. "post" -> "posts").

Specifying C<relationships> will create additional routes that fall under the resource.

Routes will point to controller actions, the names of which follow the pattern C<{http_method}_{resource}>.

B<NOTE>: Your relationships should be in the correct form (singular/plural) based on the relationship in your
schema management system. For example, if you have a resource called 'post' and it has many comments, make
sure comments is passed in as a plural noun.

=head2 render_error(I<Str> $status, I<ArrayRef> $errors, I<HashRef> $data. I<HashRef> $meta)

Renders a JSON response under the required top-level C<errors> key. C<errors> is an array reference of error objects
as described in the specification. See L<Error Objects|http://jsonapi.org/format/#error-objects>.

Can optionally provide a reference to the primary data for the route as well as meta information, which will be added
to the response as-is. Use C<resource_document> to generate the right structure for this argument.

=head2 resource_document

Available in controllers:

 $c->resource_document($dbix_row, $options);

See L<resource_document|https://metacpan.org/pod/JSONAPI::Document#resource_document(DBIx::Class::Row-$row,-HashRef-$options)> for usage.

=head2 compound_resource_document

Available in controllers:

 $c->compound_resource_document($dbix_row, $options);

See L<compound_resource_document|https://metacpan.org/pod/JSONAPI::Document#compound_resource_document(DBIx::Class::Row-$row,-HashRef-$options)> for usage.

=head2 resource_documents

Available in controllers:

 $c->resource_documents($dbix_resultset, $options);

See L<resource_documents|https://metacpan.org/pod/JSONAPI::Document#resource_documents(DBIx::Class::Row-$row,-HashRef-$options)> for usage.

=cut
