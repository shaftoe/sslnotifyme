'''Lambda report of non-expected CloudWatchLogs entry.'''
from datetime import (datetime, timedelta)
from re import match
from sys import argv
import boto3
from sslnotifyme import (APPNAME, BOUNCES_BUCKET, LOGGER, lambda_mailer, lambda_main_wrapper)


# We want only the last 25 hours worth of logs
START_TIME = datetime.utcnow() - timedelta(hours=25)


def generate_logs():
    '''Return generator to fetch CloudWatch Logs lambda events.'''
    prefix = "/aws/lambda/%s_" % APPNAME
    client = boto3.client("logs")

    groups = client.describe_log_groups(logGroupNamePrefix=prefix).get('logGroups')
    group_names = [group["logGroupName"] for group in groups]

    start_epoch = int(START_TIME.strftime('%s')) * 1000  # APIs expect milliseconds

    for group_name in group_names:
        response = client.filter_log_events(
            logGroupName=group_name,
            startTime=start_epoch,
        )
        for event in response['events']:
            yield (group_name, event)


def generate_valid_logs(exclude_regexp):
    '''Generate logs from raw CloudWatch logs generator, filter out the given regexp.'''
    for group, event in generate_logs():
        if not match(exclude_regexp, event['message']):
            yield (group, event)


def generate_bucket_objects():
    '''Return generator of BOUNCES_BUCKET objects newer then START_TIME.'''
    objs = boto3.client('s3').list_objects(Bucket=BOUNCES_BUCKET).get('Contents', [])
    for obj in objs:
        if obj['LastModified'].replace(tzinfo=None) > START_TIME:
            yield obj


class Reporter(object):
    '''Reporter object class.'''

    @staticmethod
    def get_report(exclude_regexp):
        '''Return printable report of interesting CloudWatch log events.'''
        report = ''

        for group, entry in generate_valid_logs(exclude_regexp):
            report += '%s %d %s' % (group, entry["timestamp"], entry["message"])

        for obj in generate_bucket_objects():
            report += 'Found new email bounce in %s bucket: %s\n' % (BOUNCES_BUCKET,
                                                                     obj.get('Key'))

        return report

    @staticmethod
    def send_report():
        '''Get a report from CloudWatch logs and S3, send via email.'''
        report = Reporter.get_report(exclude_regexp=r'^(START |END |REPORT |\[INFO\])')
        if report:
            return lambda_mailer('send_report', report)
        LOGGER.info('empty report')
        return {'response': 'empty report'}


# pylint: disable=unused-argument
def lambda_main(event, context):
    '''Lambda entry point.'''
    return lambda_main_wrapper(event, Reporter, default=['send_report'])


def print_usage():
    '''Print usage to STDOUT.'''
    print 'usage: %s print' % argv[0]


if __name__ == '__main__':
    if len(argv) == 1:
        print_usage()
    elif argv[1] == 'print':
        print Reporter.get_report(exclude_regexp=r'^(START |END |REPORT )')
    else:
        print_usage()
