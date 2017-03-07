'''sslnotify.me lib.'''
import json
import logging
from os import environ
import boto3

DOMAINNAME = environ.get('DOMAINNAME', 'sslnotify.me')
APPNAME = DOMAINNAME.replace(".", "")
API_URL = "https://api.%s" % DOMAINNAME
FRONTEND_URL = "https://%s" % DOMAINNAME
BOUNCES_BUCKET = "%s-ses-inbound-emails" % APPNAME
BACKUP_BUCKET = "%s-backend-backup" % APPNAME
LOGGER = logging.getLogger()
LOGGER.setLevel(logging.INFO)


def _invoke_lambda_blocking(lambda_name, *args):
    '''Invoke blocking lambda, return payload.'''
    LOGGER.info('invoking lambda_blocking %s', lambda_name)
    result = boto3.client('lambda').invoke(
        FunctionName="%s_%s" % (APPNAME, lambda_name),
        InvocationType='RequestResponse',
        Payload=json.dumps({"action": args}))
    LOGGER.info('lambda_blocking %s invoked succesfully', lambda_name)
    return json.loads(result['Payload'].read())


def _invoke_lambda_async(lambda_name, *args):
    '''Invoke async lambda mailer.'''
    LOGGER.info('invoking lambda_async %s', lambda_name)
    boto3.client('lambda').invoke(
        FunctionName="%s_%s" % (APPNAME, lambda_name),
        InvocationType='Event',
        Payload=json.dumps({"action": args}))
    LOGGER.info('lambda_async %s invoked succesfully', lambda_name)
    return {'response': 'lambda %s invoked succesfully' % lambda_name}


def lambda_mailer(*args):
    '''Invoke async lambda mailer.'''
    return _invoke_lambda_async('mailer', *args)


def lambda_mailer_blocking(*args):
    '''Invoke blocking lambda mailer.'''
    return _invoke_lambda_blocking('mailer', *args)


def lambda_db(*args):
    '''Return deserialized data from lambda db blocking invocation.'''
    return _invoke_lambda_blocking('db', *args)


def lambda_checker(*args):
    '''Invoke async lambda checker.'''
    return _invoke_lambda_async('checker', *args)


def lambda_main_wrapper(event, proxy, default=None):
    '''Wrap lambda_main request.'''
    if default and not 'action' in event:
        event['action'] = default

    if 'action' in event:
        if len(event['action']) == 0:
            return {'errorMessage':'empty action argument'}

        cmd = event['action'][0]
        args = event['action'][1:]
        func = getattr(proxy(), cmd, None)

        LOGGER.info('processing %scommand %s',
                    'default ' if default else '',
                    cmd)

        if func:
            return func(*args)
        else:
            msg = 'command %s not valid' % cmd
            LOGGER.error(msg)
            return {'errorMessage': msg}

    msg = 'action argument is mandatory'
    LOGGER.error(msg)
    return {'errorMessage': msg}
