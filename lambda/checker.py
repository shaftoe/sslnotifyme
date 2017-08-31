'''sslnotify.me lambda checker.'''
import json
import urllib.request, urllib.error, urllib.parse

from sslnotifyme import (lambda_mailer, LOGGER, lambda_main_wrapper)

SSLEXPIRED_API_URL = "http://sslexpired.info"


class Checker(object):
    '''Checker class object.'''

    @staticmethod
    def check_sslexpired(domain, days=None):
        '''Return response from sslexpired.info API.'''
        url = '%s/%s%s' % (SSLEXPIRED_API_URL, domain,
                           ('?days=%s' % days) if days else '')
        LOGGER.info('invoking %s', url)
        return json.load(urllib.request.urlopen(url))

    @staticmethod
    def check_and_send_alert(record):
        '''Send alert email if sslexpired check has alerts.'''
        if not ('domain' in record and 'days' in record):
            err = 'error: wrong record format: %s' % record
            print(err)
            return err

        try:
            result = Checker.check_sslexpired(record['domain'], record['days'])
        # pylint: disable=broad-except
        except Exception:
            msg = 'exceptions invoking %s' % SSLEXPIRED_API_URL
            LOGGER.exception(msg)
            return {'errorMessage': msg}

        if result.get('err'):
            LOGGER.error('errors found processing record: %s', result)

        if 'alert' in result:
            LOGGER.info('sending alert to %(email)s for domain %(domain)s', record)
            lambda_mailer('send_alert', record['email'], record['domain'],
                          result['response'], record['uuid'])
        else:
            LOGGER.info('domain %(domain)s for %(email)s is not in alert state', record)

        return {'response': 'ok'}


# pylint: disable=unused-argument
def lambda_main(event, context):
    '''Lambda entry point.'''
    return lambda_main_wrapper(event, Checker)
