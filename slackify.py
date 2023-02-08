import urllib3
import json
import os

http = urllib3.PoolManager()


def lambda_handler(event, context):
    slack_webhook = os.environ.get('SLACK_WEBHOOK')
    sns_message = event['Records'][0]['Sns']['Message']
    splitted_message = sns_message.split("\n")
    findings = splitted_message[3][12:-1].split(",")

    critical_findings = 0
    high_findings = 0
    medium_findings = 0
    warning_message = ":white_check_mark: No vulnerabilities found"

    for finding in findings:
        level = finding.split(':')[0]
        if level == "CRITICAL":
            critical_findings = finding.split(':')[1]
        elif level == "HIGH":
            high_findings = finding.split(':')[1]
        elif level == "MEDIUM":
            medium_findings = finding.split(':')[1]

    if int(critical_findings) > 0 or int(high_findings) > 0 or int(medium_findings) > 0:
        warning_message = ":warning: Vulnerabilities found:\n      :red_circle: CRITICAL: %s\n      :large_orange_circle: HIGH: %s\n      :large_yellow_circle: MEDIUM: %s\n" % (
        critical_findings, high_findings, medium_findings)

    sns_message = sns_message.replace(splitted_message[3], warning_message)
    splitted_message = sns_message.split("\n")
    arn = splitted_message[1]
    service = arn.split("/")[-1]
    service_name = ":k8s:: Service name: *%s*" % service
    splitted_message.insert(1, service_name)
    sns_message = "\n".join(splitted_message)
    sns_message = sns_message.replace('"', '')
    service = service.replace('"', '')
    sns_message = sns_message.replace('REPLACE_ME', service)

    msg = {
        "text": sns_message
    }
    encoded_msg = json.dumps(msg).encode('utf-8')
    resp = http.request('POST', slack_webhook, body=encoded_msg)
    print(
        {
            "message": sns_message,
            "status_code": resp.status,
            "response": resp.data
        }
    )

