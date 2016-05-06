#########################################################################
#
#	This section adds a field to the user giving them the option
#	of alerts.  If all editors are to be alerted, there is no need
#	to use this part.  You'll need to update the database on the
#	command line as this will make it impossible to log in until
#	the update is done.
#
#########################################################################

$c->add_dataset_field(
			"user",
			{
				name => 'send_review_email',
				type => 'boolean',
				input_style => "menu",
				export_as_xml => 0,
			},
		     );

#########################################################################
#
#	This section is the trigger.
#	Comments inline should explain what is happening.
#
#########################################################################

$c->add_dataset_trigger( "eprint", EP_TRIGGER_STATUS_CHANGE, sub{
    #passed to trigger are: dataobj, old_status, new_status
    my( %o ) = @_;

    my $repo = EPrints::Session->new();

    my $eprint = $o{dataobj};

    #####  Inbox are draft eprints, Buffer are eprints in the review list

    if( $o{old_status} eq "inbox" && $o{new_status} eq "buffer" ){

	#####  The subject and message are contained in phrases in z_email_editors.xml

	#####  This relates to the pins in the message phrase.
	#####  You can add to these or change them to create the message you want.
	my %parts;

	$parts{depositor} = $repo->user( $eprint->get_value( "userid" ) )->render_description;

	$parts{title} = $repo->make_text(
			EPrints::Utils::tree_to_utf8( $eprint->render_citation() )
		);
	
	$parts{edit_link} = $repo->render_link( $eprint->get_control_url() );

	my $message = $repo->html_phrase( "email_editors_body", %parts );

	#####  I've added the title to the subject phrase, but it's not necessary.
	#####  If you remove this, also change the phrase file.
        my $subject = $repo->phrase(
				"email_editors_subject",
				title => $eprint->get_value( "title" ) );

	#####  Gets the dataset containing the editors (i.e. "user" )
	my $editors_ds = $repo->dataset( "user" );

	#####  Sets up the search
	my $searchexp = EPrints::Search->new(
		session => $repo,
		dataset => $editors_ds );

	#####  Checks to see whether the user wants an immediate email
	#####  If you didn't add this field above, remove this line
	$searchexp->add_field(
		$editors_ds->get_field( "send_review_email" ),
		'TRUE' );

	my $fn = sub {
		my( $session, $dataset, $user, $info ) = @_;

		#####  Will eliminate any user who has set the field but isn't an editor
		return unless( $user->has_role( "editor" ) );

		#####  Should check whether the user can edit it.  I don't have any limited users set up so can't test.
		return unless( $eprint->in_editorial_scope_of( $user ) );

		# change language temporarily to the user's language
		local $repo->{lang} = $user->language();

		##### This builds the email.  You may be using send_mail instead.
		EPrints::Email::send_mail_via_smtp(
						session  => $repo,
						langid   => $user->get_value( "lang" ),
						to_name  => EPrints::Utils::tree_to_utf8( $user->render_description ),
						to_email => $user->get_value( "email" ),
						subject  => $subject,
						message  => $message,
						sig      => $repo->{lang}->phrase( "mail_sig", {}, $repo ),
						from_name  => $repo->phrase( "archive_name" ), 
						from_email => $repo->config( "adminemail" ),
						replyto_name  => $repo->phrase( "archive_name" ), 
						replyto_email => $repo->config( "adminemail" ),
					);
	};

	#####  This searches for users and looks to send emails to each of them.	
	my $list = $searchexp->perform_search;
	$list->map( $fn, {} );	

    }

    return EP_TRIGGER_OK;
});
