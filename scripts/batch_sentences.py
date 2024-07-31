"""
Process sentences for GenFact in a batch.
"""

from argparse import ArgumentParser
import json
import logging
import math
import os
from pathlib import Path
import string
import requests
from requests.auth import HTTPBasicAuth
import time

logger = logging.getLogger(__name__)


REPO_ROOT = Path(__file__).resolve().parent.parent
RESOURCES_ROOT = REPO_ROOT / 'resources'

PROMPT_TEMPLATE_PATH = RESOURCES_ROOT / 'templates' / 'json_prompt_template.txt'
GRAMMAR_PATH = RESOURCES_ROOT / 'json_grammar.lark'
DEFAULT_BATCH_SIZE = 10

HTML_TEMPLATE = string.Template(
    """<!DOCTYPE html>
<html lang="en">
    <head>
        <meta charset="utf-8">
        <title>GenFact batch output for batch $batch_no (sentences $start_sent to $end_sent)</title>
    </head>
    <body>
        <style>
            table, th, td {
              border: 1px solid black;
              border-collapse: collapse;
            }
        </style>
$tables
    </body>
</html>"""
)
TABLE_TEMPLATE = string.Template(
    """<table>
    <tr>
        <th>Annotated Sentence</th>
        <th>Likelihood</th>
    </tr>
$rows
</table>"""
)

# IP and connection related
HTTP_TIMEOUT_CODE = 504  # https://developer.mozilla.org/en-US/docs/Web/HTTP/Status/504
DEFAULT_GENFACT_SERVER_IP = '34.44.35.203'
GENFACT_ENDPOINT_FORMAT = string.Template('http://$ip:8888/sentence-to-doctor-data')

DEFAULT_GENPARSE_SERVER_IP = '34.122.30.137'
ALTERNATE_SERVER_IP = '34.70.201.1'

connect_timeout_seconds = 3.05

inference_endpoint_format = string.Template('http://$ip:8888/infer')
inference_timeout_seconds = 120
post_restart_inference_timeout_seconds = 300
WAIT_FOR_GENPARSE_REBOOT = 60
WAIT_FOR_GENPARSE_REBOOT_LONG = 30

restart_endpoint_format = string.Template('http://$ip:9999/restart')
restart_timeout_seconds = 30


def get_restart_user():
    return os.getenv('GENPARSE_USER')


def get_restart_password():
    return os.getenv('GENPARSE_PASSWORD')


def request_timeout(timeout):
    return (connect_timeout_seconds, timeout)


def restart_server(ip: str):
    "Restart the Genparse server at the given IP."
    url = restart_endpoint_format.substitute(ip=ip)
    basic = HTTPBasicAuth(get_restart_user(), get_restart_password())
    result = requests.post(url, auth=basic, timeout=request_timeout(restart_timeout_seconds))
    assert result.status_code == 200
    logger.debug('Sleeping for %d waiting for genparse to reboot', WAIT_FOR_GENPARSE_REBOOT)
    time.sleep(WAIT_FOR_GENPARSE_REBOOT)
    return result


def run_inference_genfact_server(sentence: str, *, ip: str = DEFAULT_GENFACT_SERVER_IP):
    """
    Run inference using the Genfact server.
    """
    url = GENFACT_ENDPOINT_FORMAT.substitute(ip=ip)
    params = {'sentence': sentence}
    headers = {
        'Content-type': 'application/json',
        'Accept': 'application/json',
    }
    response = requests.post(url, json=params, headers=headers)
    try:
        if 'posterior' not in response.json():
            logger.debug("Got bad response from server: %s, sleeping for %d", response.json(), WAIT_FOR_GENPARSE_REBOOT_LONG)
            time.sleep(WAIT_FOR_GENPARSE_REBOOT_LONG)
            response = requests.post(url, json=params, headers=headers)
    except json.JSONDecodeError:
        raise
    return response


def format_as_html_table(response, *, sentence: str):
    result: str = (
        f'<p>Something went wrong with processing {sentence}: '
        f'when contacting GenFact server, got HTTP staus code '
        f'{response.status_code} with content {response.content}.</p>'
    )
    try:
        data = response.json()
        posterior = dict(sorted(data['posterior'].items(), key=lambda t: (t[1]['likelihood'], t[0]), reverse=True))

        rows = []
        for html, response_data in posterior.items():
            likelihood = response_data['likelihood']
            rows.append(
                f"""<tr>
    <td>{html}</td>
    <td>{100.0 * likelihood:.1f}%</td>
</tr>"""
            )
        logger.debug("Response includes %d rows", len(rows))
        result = TABLE_TEMPLATE.substitute(rows='\n'.join(rows))
    except json.JSONDecodeError as e:
        result = (
            f'<p>Something went wrong with processing {sentence}: '
            f'response from GenFact server was not JSON. Error: {e}'
        )
    return result


def main():
    parser = ArgumentParser(description=__doc__)
    parser.add_argument(
        'sentences_path', type=Path, help='Path to the text file of sentences (one per line).'
    )
    parser.add_argument(
        'save_outputs_to', type=Path, help='Directory where we save the batches of outputs.'
    )
    parser.add_argument(
        '--genfact-ip',
        type=str,
        default=DEFAULT_GENFACT_SERVER_IP,
        help='GenFact server IP to use.',
    )
    parser.add_argument(
        '--genparse-ip',
        type=str,
        default=DEFAULT_GENPARSE_SERVER_IP,
        help='Genparse server IP to restart.',
    )
    parser.add_argument(
        '--logging-level',
        type=str,
        default='INFO',
        help='Logging level to use.',
    )
    args = parser.parse_args()

    logging.basicConfig(
        level=getattr(logging, args.logging_level),
        format='%(asctime)s - %(levelname)s - %(name)s -   %(message)s',
        datefmt='%Y-%m-%d %H:%M:%S',
    )

    sentences_path: Path = args.sentences_path
    save_outputs_to: Path = args.save_outputs_to
    genfact_ip: str = args.genfact_ip
    genparse_ip: str = args.genparse_ip

    save_outputs_to.mkdir(parents=True, exist_ok=True)

    # restart it BAE just in case previous queries have filled the cache
    logger.info('Restarting Genparse server at %s', genparse_ip)
    restart_server(genparse_ip)

    sentences = sentences_path.read_text(encoding='utf-8').splitlines()
    batch_size = DEFAULT_BATCH_SIZE
    batch = []
    start_sent = 1
    batch_no = 1
    expected_batch_total = math.ceil(len(sentences) / batch_size)
    while sentences or batch:
        if not batch:
            logger.info('Starting batch %d', batch_no)
            batch = sentences[:batch_size]
            sentences = sentences[batch_size:]
            end_sent = start_sent + len(batch)
        else:
            logger.info('Rerunning batch %d', batch_no)

        sections = []
        timing_out = False
        for sent_no, sentence in enumerate(batch, start=1):
            logger.debug('Requesting sentence %d of %d in batch %d', sent_no, len(batch), batch_no)
            response = run_inference_genfact_server(sentence, ip=genfact_ip)
            if response.status_code == HTTP_TIMEOUT_CODE:
                logger.debug('TIMEOUT on sentence %d of %d in batch %d', sent_no, len(batch), batch_no)
                timing_out = True
                break
            html_table = format_as_html_table(response, sentence=sentence)
            section = f"""<h2>{sentence}</h2>
{html_table}"""
            sections.append(section)

        if timing_out:
            logger.debug('TIMEOUT on batch %d with batch size %d', batch_no, batch_size)
            raise ValueError('oops, we broke the server :(')
            batch_size = batch_size // 2
            continue
        html = HTML_TEMPLATE.substitute(batch_no=batch_no, start_sent=start_sent, end_sent=end_sent, tables='\n'.join(sections))
        html_path = save_outputs_to / f'genfact_batch{batch_no}_of_expected_{expected_batch_total}.html'
        html_path.write_text(html)
        logger.info('Wrote results for batch %d to %s', batch_no, html_path)

        logger.info('Restarting Genparse server at %s', genparse_ip)
        restart_server(genparse_ip)

        start_sent += len(batch)
        batch = []
        batch_no += 1




if __name__ == '__main__':
    main()