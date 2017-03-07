'''cron function.

Scans the user table and, for each user, invokes one lambda checker.
If the check generates an alert, invokes mailer lambda to notify the user.'''
from sslnotifyme import (lambda_db, lambda_checker, lambda_main_wrapper, LOGGER)


class Cron(object):
    '''Cron object class.'''

    @staticmethod
    def scan_and_notify_alerts_queue():
        '''Trigger a lambda checker for each validated user.'''
        counter = 0
        for record in lambda_db('get_validated_users').get('response'):
            lambda_checker('check_and_send_alert', record)
            counter += 1
        msg = '%d record(s) processed successfully' % counter
        LOGGER.info(msg)
        return {'response': msg}


# pylint: disable=unused-argument
def lambda_main(event, context):
    '''Lambda entry point.'''
    return lambda_main_wrapper(event, Cron,
                               default=['scan_and_notify_alerts_queue'])
