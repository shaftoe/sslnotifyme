'''email sending function.'''
from os import environ
import boto3
from botocore.exceptions import ClientError
from sslnotifyme import (lambda_main_wrapper, APPNAME, DOMAINNAME, FRONTEND_URL, LOGGER)

FROM_EMAIL = environ.get('FROM_EMAIL', "%s <noreply@%s>" % (DOMAINNAME, DOMAINNAME))
FEEDBACK_EMAIL = environ.get('FEEDBACK_EMAIL', "feedback@%s" % DOMAINNAME)
REPORT_TO_EMAIL = environ.get('REPORT_TO_EMAIL', 'report@%s' % DOMAINNAME)


def send_ses_email(send_to, subject, body, tag='notag'):
    '''Send SES email.'''
    boto3.client('ses').send_email(
        Source=FROM_EMAIL,
        Destination={'ToAddresses': [send_to]},
        Message={'Subject': {'Data': subject},
                 'Body': {'Text': {'Data': body}}},
        # https://docs.aws.amazon.com/ses/latest/DeveloperGuide/monitor-sending-activity.html
        ConfigurationSetName=APPNAME,
        Tags=[{'Name': 'emailType',
               'Value': '%s%s' % (APPNAME, tag)}])


class Mailer(object):
    '''Mailer object.'''

    @staticmethod
    def send_alert(email, domain, message, uuid):
        '''Send alert email via SES.'''
        link = '%s/unsubscribe.html?user=%s&uuid=%s' % (FRONTEND_URL, email, uuid)
        body = '''%s

You will receive this alert every day until a new certificate has been issued to replace the current one.

To disable the alert, unsubscribe following this link: %s

-- 
%s
''' % (message, link, DOMAINNAME)
        try:
            LOGGER.info('sending alert message for domain %s to %s', domain, email)
            send_ses_email(email, 'SSL alert for domain %s' % domain, body, 'ExpiryAlert')
            return {'response': 'email sent successfully'}
        except ClientError:
            LOGGER.exception('exception sending alert email to %s', email)
            return {'errorMessage': 'internal error delivering email to the '
                                    'email system, please try again later'}

    @staticmethod
    def send_activation_link(email, domain, days, uuid):
        '''Send link to email address via SES.'''
        link = '%s/confirm.html?user=%s&uuid=%s' % (FRONTEND_URL, email, uuid)
        body = '''Hello,

you have requested to be notified if and when the SSL certificate for domain "%s"
will expire in the following %d days.

To enable the service, please verify your email address clicking on the following link:

%s

-- 
%s
''' % (domain, days, link, DOMAINNAME)
        try:
            LOGGER.info('sending activation link %s for domain %s', link, domain)
            send_ses_email(email, 'Confirm subscription to %s' % DOMAINNAME, body, 'ValidationLink')
            return {'response': 'Please check your emails to confirm your subscription'}
        except ClientError:
            LOGGER.exception('exception sending confirmation email to %s', email)
            return {'errorMessage': 'Error sending confirmation email, '
                                    'please ensure your email address is valid and that '
                                    'your mailbox is not full'}

    @staticmethod
    def send_feedback(content):
        '''Send feedback data to email address via SES.'''
        try:
            LOGGER.info('sending feedback mail')
            send_ses_email(FEEDBACK_EMAIL, 'Form feedback entry', content, tag='Feedback')
            return {'response': 'thank you for your submission'}
        except ClientError:
            LOGGER.exception('exception sending feedback email')
            return {'errorMessage': 'Error sending feedback email, '
                                    'please try later'}

    @staticmethod
    def send_report(report):
        '''Send daily report via SES.'''
        try:
            LOGGER.info('sending report mail')
            send_ses_email(REPORT_TO_EMAIL, 'Daily report', report, tag='DailyReport')
            return {'response': 'report sent via email'}
        except ClientError:
            LOGGER.exception('exception sending feedback email')
            return {'errorMessage': 'Internal error sending report email'}


# pylint: disable=unused-argument
def lambda_main(event, context):
    '''Lambda entry point.'''
    return lambda_main_wrapper(event, Mailer)
