name: Prometheus Job Processor
on:
  repository_dispatch:
    types: [prometheus-job-start]

jobs:
  obfuscate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: install dependencies
        run: |
          sudo apt-get update
          sudo apt-get install -y luajit jq

      - name: run obfuscator
        id: run_obfuscator
        env:
          USER_CODE: ${{ github.event.client_payload.code || '' }}
          PROM_PRESET: ${{ github.event.client_payload.preset || 'Strong' }}
        run: |
          chmod +x ./runner.lua || true
          OUTPUT=$(luajit ./runner.lua 2> stderr.log)
          echo "exit_code=$?" >> $GITHUB_ENV

          # set multiline outputs
          DELIMITER_RESULT=$(openssl rand -hex 16)
          echo "result<<$DELIMITER_RESULT" >> $GITHUB_OUTPUT
          echo "$OUTPUT" >> $GITHUB_OUTPUT
          echo "$DELIMITER_RESULT" >> $GITHUB_OUTPUT

          DELIMITER_ERROR=$(openssl rand -hex 16)
          echo "error_log<<$DELIMITER_ERROR" >> $GITHUB_OUTPUT
          cat stderr.log >> $GITHUB_OUTPUT
          echo "$DELIMITER_ERROR" >> $GITHUB_OUTPUT

      - name: report success to vercel
        if: ${{ env.exit_code == '0' }}
        env:
          VERCEL_WEBHOOK_URL: ${{ secrets.VERCEL_COMPLETE_URL }}
          WORKER_SECRET: ${{ secrets.WORKER_SECRET }}
          OBFUSCATED_CODE: ${{ steps.run_obfuscator.outputs.result }}
        run: |
          # get job id directly inside run so it resolves properly
          JOB_ID="${{ github.event.client_payload.job_id }}"
          echo "JOB_ID: $JOB_ID (len: ${#JOB_ID})"

          # clean up secrets
          export VERCEL_WEBHOOK_URL="$(echo "$VERCEL_WEBHOOK_URL" | tr -d '\n\r \t')"
          export WORKER_SECRET="$(echo "$WORKER_SECRET" | tr -d '\n\r \t')"

          echo "--- DIAGNOSTIC START ---"
          echo "VERCEL_URL_LENGTH: ${#VERCEL_WEBHOOK_URL}"
          echo "WORKER_SECRET_START: ${WORKER_SECRET:0:8}"
          echo "--- DIAGNOSTIC END ---"

          # write code to file
          echo "$OBFUSCATED_CODE" > obfuscated_code.txt

          # build payload
          jq -n \
            --arg jid "$JOB_ID" \
            --rawfile code obfuscated_code.txt \
            '{ "jobId": $jid, "status": "COMPLETED", "obfuscatedCode": $code, "error": null }' > payload.json

          # post to vercel
          curl -f -X POST "$VERCEL_WEBHOOK_URL" \
            -H "Content-Type: application/json" \
            -H "Authorization: Bearer $WORKER_SECRET" \
            --data-binary @payload.json

      - name: report failure to vercel
        if: ${{ env.exit_code != '0' }}
        env:
          VERCEL_WEBHOOK_URL: ${{ secrets.VERCEL_COMPLETE_URL }}
          WORKER_SECRET: ${{ secrets.WORKER_SECRET }}
          ERROR_MESSAGE: ${{ steps.run_obfuscator.outputs.error_log }}
        run: |
          JOB_ID="${{ github.event.client_payload.job_id }}"
          echo "JOB_ID: $JOB_ID (len: ${#JOB_ID})"

          export VERCEL_WEBHOOK_URL="$(echo "$VERCEL_WEBHOOK_URL" | tr -d '\n\r \t')"
          export WORKER_SECRET="$(echo "$WORKER_SECRET" | tr -d '\n\r \t')"

          echo "$ERROR_MESSAGE" > error_message.txt

          jq -n \
            --arg jid "$JOB_ID" \
            --rawfile err error_message.txt \
            '{ "jobId": $jid, "status": "FAILED", "obfuscatedCode": null, "error": $err }' > payload.json

          curl -f -X POST "$VERCEL_WEBHOOK_URL" \
            -H "Content-Type: application/json" \
            -H "Authorization: Bearer $WORKER_SECRET" \
            --data-binary @payload.json
