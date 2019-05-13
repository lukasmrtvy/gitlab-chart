_CRD_NAME='{{ template "gitlab.operator.crdName" . }}'

printf 'Creating CRD `%s` ...\n' "$_CRD_NAME"
kubectl apply -f "$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null 2>&1 && pwd )/crd.yaml"

printf 'Waiting for CRD `%s` to become available ...\n' "$_CRD_NAME"
_cnt=0
_max=10 # 10ms
while [ $_cnt -lt $_max ]; do
  _out="$( kubectl get crd $_CRD_NAME 2>&1 )"
  [ "$?" = "0" ] && {
      printf 'CRD `%s` is available and ready to use.\n' "$_CRD_NAME"
      exit 0
  }
  [[ ! "$_out" =~ \(NotFound\) ]] && {
      printf 'Premature failure in CRD lookup. Reason: \n\t[kubectl] %s\n' "$_out"
      exit 2
  }
  let _cnt=_cnt+1
  sleep 1
done

printf 'Timed out. CRD `%s` did not become available in time' "$_CRD_NAME"
exit 1