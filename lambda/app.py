'''sslnotify.me Chalice backend.'''
from botocore.exceptions import ClientError
from chalice import (Chalice, ChaliceViewError, BadRequestError)
from chalicelib import (lambda_db, lambda_mailer_blocking, APPNAME, LOGGER)


# XXX for now Chalice doesn't support environment variables, hence we can't assume
# APPNAME is not defaulted to sslnotifyme:
# https://github.com/awslabs/chalice/issues/257
app = Chalice(app_name=APPNAME)


def log_request():
    '''Send request info to CloudWatch.'''
    LOGGER.info('processing request method:%s uri_params:%s query_params:%s data:%s',
                app.current_request.method,
                app.current_request.uri_params,
                app.current_request.query_params,
                app.current_request.raw_body)


@app.route('/feedback', methods=['POST'], cors=True)
def feedback_router():
    '''Process /feedback request.'''
    log_request()
    return process_lambda_output(
        # Send all the POST data to feedback mailbox
        lambda_mailer_blocking('send_feedback', app.current_request.raw_body))


@app.route('/user/{user}', methods=['PUT', 'DELETE'], cors=True)
def user_router(user):
    '''Dispatch /user request.'''
    log_request()

    if not user:
        raise BadRequestError('user is mandatory')

    methods_mapping = {
        'PUT': add_user,
        'DELETE': delete_user,
    }
    return methods_mapping[app.current_request.method](user)


def add_user(user):
    '''Add user to proper users table.'''
    params = app.current_request.query_params

    if params and params.get('uuid'):
        # user is providing authentication token, we add to valid users table

        output = lambda_db("validate_pending_user", user, params["uuid"])
        return process_lambda_output(output)

    if params and params.get('domain'):
        # no auth token provided, we just add user to pending table

        if params.get('days'):
            try:
                days = int(params['days'])
                if days < 1:
                    raise ValueError
            except ValueError, err:
                raise BadRequestError('days value must be a positive number')

        else:
            days = 30  # set default value for days tolerance

        try:
            output = lambda_db("put_user_to_pending", user, params['domain'], days)
            if not output.get('uuid'):
                raise BadRequestError('missing expected uuid from output')
            uuid = output['uuid']
            output = lambda_mailer_blocking('send_activation_link',
                                            user, params['domain'], days, uuid)
            return process_lambda_output(output)

        except ClientError, err:
            raise BadRequestError('%s' % err)

    raise BadRequestError('must provide either domain or uuid parameter')


def delete_user(user):
    '''Verify uuid matches user, and delete if so.'''
    params = app.current_request.query_params

    if params and params.get('uuid'):
        output = lambda_db("delete_validated_user", user, params['uuid'])
        return process_lambda_output(output)

    else:
        raise BadRequestError('uuid parameter is mandatory')


def process_lambda_output(output):
    '''Return processed lambda output, raise errors if found.'''
    if output.get('response'):
        return {"Message": output["response"]}

    elif output.get('errorMessage'):
        raise BadRequestError(output['errorMessage'])

    else:
        raise ChaliceViewError('unexpected output '
                               'from lambda call: %s' % str(output))
